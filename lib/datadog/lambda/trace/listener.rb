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
      def initialize(handler_name:, function_name:, patch_http:,
                     merge_xray_traces:)
        @handler_name = handler_name
        @function_name = function_name
        @merge_xray_traces = merge_xray_traces

        Datadog::Trace.patch_http if patch_http
      end

      def on_start(event:)
        trace_context = Datadog::Trace.extract_trace_context(event,
                                                             @merge_xray_traces)
        Datadog::Trace.trace_context = trace_context
        Datadog::Utils.logger.debug "extracted trace context #{trace_context}"
      rescue StandardError => e
        Datadog::Utils.logger.error "couldn't read tracing context #{e}"
      end

      def on_end; end

      def on_wrap(request_context:, cold_start:, &block)
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
        Datadog::Trace.wrap_datadog(options) do
          block.call
        end
      end

      private

      def get_option_tags(request_context:, cold_start:)
        function_arn = request_context.invoked_function_arn.downcase
        tk = function_arn.split(':')
        function_arn = tk.length > 7 ? tk[0, 7].join(':') : function_arn
        function_version = tk.length > 7 ? tk[7] : '$LATEST'
        options = {
          tags: {
            cold_start: cold_start,
            function_arn: function_arn,
            function_version: function_version,
            request_id: request_context.aws_request_id,
            resource_names: request_context.function_name
          }
        }
        options
      end
    end
  end
end
