# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

require 'datadog/lambda/trace/context'
require 'datadog/lambda/trace/patch_http'
require 'datadog/lambda/trace/ddtrace'

module Datadog
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      @trace = nil
      def initialize(handler_name:, function_name:, patch_http:,
                     merge_xray_traces:)
        @handler_name = handler_name
        @function_name = function_name
        @merge_xray_traces = merge_xray_traces
        @appsec_context = nil
        @gateway_request = nil

        Datadog::Trace.patch_http if patch_http
      end

      # rubocop:disable Metrics/AbcSize
      def on_start(event:, request_context:, cold_start:)
        trace_context = Datadog::Trace.extract_trace_context(event, @merge_xray_traces)
        Datadog::Trace.trace_context = trace_context
        Datadog::Utils.logger.debug "extracted trace context #{trace_context}"
        options = get_option_tags(
          request_context:,
          cold_start:
        )
        context = Datadog::Trace.trace_context
        source = context[:source] if context
        options[:tags]['_dd.parent_source'] = source if source && source != 'ddtrace'
        options[:resource] = 'dd-tracer-serverless-span'
        options[:service] = 'aws.lambda'
        options[:type] = 'serverless'

        trace_digest = Datadog::Utils.send_start_invocation_request(event:, request_context:)
        options[:continue_from] = trace_digest if trace_digest

        @trace = Datadog::Tracing.trace('aws.lambda', **options)

        Datadog::Trace.apply_datadog_trace_context(Datadog::Trace.trace_context)

        start_appsec(event)
      end
      # rubocop:enable Metrics/AbcSize

      def on_end(response:, request_context:)
        finish_appsec(response)
        Datadog::Utils.send_end_invocation_request(response:, span_id: @trace.id, request_context:, span: @trace)
        @trace&.finish
      end

      private

      def start_appsec(event)
        return unless appsec_enabled?

        ensure_appsec_patched

        security_engine = Datadog::AppSec.security_engine
        return unless security_engine

        active_trace = Datadog::Tracing.active_trace
        @appsec_context = Datadog::AppSec::Context.activate(
          Datadog::AppSec::Context.new(active_trace, @trace, security_engine.new_runner)
        )

        @trace.set_metric(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)

        @gateway_request = Datadog::AppSec::Contrib::AwsLambda::Gateway::Request.new(event)
        Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.request.start', @gateway_request)
      rescue StandardError => e
        Datadog::Utils.logger.debug "failed to start AppSec context: #{e}"
      end

      def finish_appsec(response)
        return unless @appsec_context

        gateway_response = Datadog::AppSec::Contrib::AwsLambda::Gateway::Response.new(
          response, context: @appsec_context
        )
        Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.response.start', gateway_response)

        Datadog::AppSec::Event.record(@appsec_context, request: @gateway_request)

        @appsec_context.export_metrics
        @appsec_context.export_request_telemetry
      rescue StandardError => e
        Datadog::Utils.logger.debug "failed to finish AppSec context: #{e}"
      ensure
        Datadog::AppSec::Context.deactivate
        @appsec_context = nil
        @gateway_request = nil
      end

      def appsec_enabled?
        defined?(Datadog::AppSec) &&
          Datadog::AppSec.respond_to?(:enabled?) &&
          Datadog::AppSec.enabled?
      end

      def ensure_appsec_patched
        return if @appsec_patched

        Datadog.configuration.appsec.instrument(:aws_lambda)
        @appsec_patched = true
      end

      def get_option_tags(request_context:, cold_start:)
        function_arn = request_context.invoked_function_arn.to_s.downcase
        tk = function_arn.split(':')
        function_arn = tk.length > 7 ? tk[0, 7].join(':') : function_arn
        function_version = tk.length > 7 ? tk[7] : '$LATEST'
        function_name = request_context.function_name
        {
          tags: {
            cold_start:,
            function_arn:,
            function_version:,
            request_id: request_context.aws_request_id,
            functionname: function_name.nil? || function_name.empty? ? nil : function_name.downcase,
            resource_names: function_name
          }
        }
      end
    end
  end
end
