# frozen_string_literal: true

require 'ddlambda/trace/context'
require 'ddlambda/trace/xray_lambda'
require 'ddlambda/trace/patch_http'

require 'aws-xray-sdk'

module DDLambda
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      def initialize
        XRay.recorder.configure(
          patch: %I[net_http aws_sdk],
          context: DDLambda::Trace::LambdaContext.new,
          streamer: DDLambda::Trace::LambdaStreamer.new,
          emitter: DDLambda::Trace::LambdaEmitter.new
        )
        DDLambda::Trace.patch_http
      end

      def on_start(event:)
        DDLambda::Trace.trace_context =
          DDLambda::Trace.extract_trace_context(event)
      rescue StandardError => e
        puts "couldn't read tracing context #{e}"
      end

      def on_end; end
    end
  end
end
