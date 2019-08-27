# frozen_string_literal: true

require 'datadog_lambda/trace/context'
require 'datadog_lambda/trace/xray_lambda'
require 'datadog_lambda/trace/patch_http'

require 'aws-xray-sdk'

module DDLambda
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      def initialize
        XRay.recorder.configure(
          patch: %I[aws_sdk],
          context: DDLambda::Trace::LambdaContext.new,
          streamer: DDLambda::Trace::LambdaStreamer.new,
          emitter: DDLambda::Trace::LambdaEmitter.new
        )
        DDLambda::Trace.patch_http
      end

      def on_start(event:)
        trace_context = DDLambda::Trace.extract_trace_context(event)
        DDLambda::Trace.trace_context = trace_context
        DDLambda::Utils.logger.debug "extracted trace context #{trace_context}"
      rescue StandardError => e
        DDLambda::Utils.logger.error "couldn't read tracing context #{e}"
      end

      def on_end; end
    end
  end
end
