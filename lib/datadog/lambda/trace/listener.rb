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
        @inferred_span = nil

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

        @inferred_span = create_inferred_span(event, request_context, trace_digest)
        options[:continue_from] = trace_digest if trace_digest && !@inferred_span

        @trace = Datadog::Tracing.trace('aws.lambda', **options)

        Datadog::Trace.apply_datadog_trace_context(Datadog::Trace.trace_context)

        start_appsec(event)
      end
      # rubocop:enable Metrics/AbcSize

      def on_end(response:, request_context:)
        finish_appsec(response)
        Datadog::Utils.send_end_invocation_request(response:, span_id: @trace.id, request_context:, span: @trace)
        @trace&.finish
        finish_inferred_span(response)
      end

      private

      def create_inferred_span(event, request_context, trace_digest)
        return unless managed_services_enabled?

        span_name = inferred_span_name(event)
        return unless span_name

        rc = event['requestContext'] || {}
        domain = rc['domainName'] || ''
        api_id = rc['apiId'] || ''
        stage = rc['stage'] || ''

        if span_name == 'aws.apigateway'
          method = event['httpMethod']
          path = event['path'] || '/'
          resource_path = rc['resourcePath'] || path
          request_time_ms = rc['requestTimeEpoch']
          user_agent = rc.dig('identity', 'userAgent')
        else
          http = rc['http'] || {}
          method = http['method']
          path = event['rawPath'] || '/'
          resource_path = event['routeKey']&.sub(/^[A-Z]+ /, '') || path
          request_time_ms = rc['timeEpoch']
          user_agent = http['userAgent']
        end

        resource = "#{method} #{resource_path}"
        http_url = domain.empty? ? path : "https://#{domain}#{path}"

        tags = {
          'http.method' => method,
          'http.url' => http_url,
          'http.route' => resource_path,
          'endpoint' => path,
          'resource_names' => resource,
          'span.kind' => 'server',
          'apiid' => api_id,
          'apiname' => api_id,
          'stage' => stage,
          'request_id' => request_context.aws_request_id,
          '_inferred_span.synchronicity' => 'sync',
          '_inferred_span.tag_source' => 'self',
        }

        arn = request_context.invoked_function_arn.to_s
        region = arn.split(':')[3] if arn.include?(':')
        if region && !api_id.empty? && !stage.empty?
          arn_path = span_name == 'aws.apigateway' ? 'restapis' : 'apis'
          tags['dd_resource_key'] = "arn:aws:apigateway:#{region}::/#{arn_path}/#{api_id}/stages/#{stage}"
        end

        tags['http.useragent'] = user_agent if user_agent

        inferred_options = {
          service: domain.empty? ? nil : domain,
          resource: resource,
          type: 'web',
          tags: tags,
        }
        inferred_options[:continue_from] = trace_digest if trace_digest
        inferred_options[:start_time] = Time.at(request_time_ms / 1000.0) if request_time_ms

        span = Datadog::Tracing.trace(span_name, **inferred_options)
        span.set_metric('_dd._inferred_span', 1.0)
        span
      rescue StandardError => e
        Datadog::Utils.logger.debug "failed to create inferred span: #{e}"
        nil
      end

      def finish_inferred_span(response)
        return unless @inferred_span

        if @trace
          appsec_enabled = @trace.get_metric('_dd.appsec.enabled')
          @inferred_span.set_metric('_dd.appsec.enabled', appsec_enabled) if appsec_enabled

          appsec_json = @trace.get_tag('_dd.appsec.json')
          @inferred_span.set_tag('_dd.appsec.json', appsec_json) if appsec_json

          appsec_event = @trace.get_tag('appsec.event')
          @inferred_span.set_tag('appsec.event', appsec_event) if appsec_event

          origin = @trace.get_tag('_dd.origin')
          @inferred_span.set_tag('_dd.origin', origin) if origin
        end

        status_code = extract_status_code(response)
        @inferred_span.set_tag('http.status_code', status_code.to_s) if status_code

        @inferred_span.finish
      rescue StandardError => e
        Datadog::Utils.logger.debug "failed to finish inferred span: #{e}"
      ensure
        @inferred_span = nil
      end

      def inferred_span_name(event)
        return unless event.is_a?(Hash)

        rc = event['requestContext']
        return unless rc.is_a?(Hash) && rc['stage']

        if event['httpMethod']
          'aws.apigateway'
        elsif event['routeKey']
          'aws.httpapi'
        end
      end

      def managed_services_enabled?
        ENV.fetch('DD_TRACE_MANAGED_SERVICES', 'true').downcase != 'false'
      end

      def extract_status_code(response)
        return unless response.is_a?(Hash)

        response['statusCode']
      end

      def start_appsec(event)
        return unless appsec_enabled?

        ensure_appsec_patched

        Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.request.start', event)
      rescue StandardError => e
        Datadog::Utils.logger.debug "failed to start AppSec: #{e}"
      end

      def finish_appsec(response)
        return unless Datadog::AppSec::Context.active

        Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.response.start', response)
      rescue StandardError => e
        Datadog::Utils.logger.debug "failed to finish AppSec: #{e}"
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
