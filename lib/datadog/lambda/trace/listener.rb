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

        Datadog::Trace.patch_http if patch_http
      end

      # rubocop:disable Metrics/AbcSize
      def on_start(event:, request_context:, cold_start:)
        trace_context = Datadog::Trace.extract_trace_context(event, @merge_xray_traces)
        Datadog::Trace.trace_context = trace_context
        Datadog::Utils.logger.debug "extracted trace context #{trace_context}"
        options = get_option_tags(
          request_context: request_context,
          cold_start: cold_start
        )
        context = Datadog::Trace.trace_context
        source = context[:source] if context
        options[:tags]['_dd.parent_source'] = source if source && source != 'ddtrace'
        options[:resource] = @function_name
        options[:service] = 'aws.lambda'
        options[:span_type] = 'serverless'
        Datadog::Trace.apply_datadog_trace_context(Datadog::Trace.trace_context)
        trace_digest = Datadog::Utils.send_start_invocation_request(event: event)
        options[:continue_from] = trace_digest if trace_digest
        @trace = Datadog::Tracing.trace('aws.lambda', **options)
      end
      # rubocop:enable Metrics/AbcSize

      def on_end(response:)
        Datadog::Utils.send_end_invocation_request(response: response)
        @trace&.finish
      end

      private

      def get_option_tags(request_context:, cold_start:)
        function_arn = request_context.invoked_function_arn.to_s.downcase
        tk = function_arn.split(':')
        function_arn = tk.length > 7 ? tk[0, 7].join(':') : function_arn
        function_version = tk.length > 7 ? tk[7] : '$LATEST'
        function_name = request_context.function_name
        options = {
          tags: {
            cold_start: cold_start,
            function_arn: function_arn,
            function_version: function_version,
            request_id: request_context.aws_request_id,
            functionname: function_name.nil? || function_name.empty? ? nil : function_name.downcase,
            resource_names: function_name
          }
        }
        options
      end
    end
  end
end
