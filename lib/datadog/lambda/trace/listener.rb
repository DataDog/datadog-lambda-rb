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
require 'datadog/lambda/inferred_span'
require 'datadog/lambda/appsec'

module Datadog
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      def initialize(handler_name:, function_name:, patch_http:,
                     merge_xray_traces:)
        @handler_name = handler_name
        @function_name = function_name
        @merge_xray_traces = merge_xray_traces
        @span = nil
        @inferred_span = nil

        Datadog::Trace.patch_http if patch_http
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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

        @inferred_span = Datadog::Lambda::InferredSpan.create(event, request_context, trace_digest)
        options[:continue_from] = trace_digest if trace_digest && @inferred_span.nil?

        @span = Datadog::Tracing.trace('aws.lambda', **options)

        Datadog::Trace.apply_datadog_trace_context(Datadog::Trace.trace_context)
        Datadog::Lambda::AppSec.on_start(
          event, trace: Datadog::Tracing.active_trace, span: @inferred_span || @span
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def on_end(response:, request_context:)
        Datadog::Lambda::AppSec.on_finish(response)
        Datadog::Utils.send_end_invocation_request(span_id: @span.id, response:, request_context:)

        # NOTE: lambda span must finish before inferred span (its parent)
        @span&.finish
        @inferred_span&.finish

        @span = nil
        @inferred_span = nil
      end

      private

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
