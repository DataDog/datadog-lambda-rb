# frozen_string_literal: true

require 'ddlambda/trace/context'
require 'ddlambda/trace/xray_lambda'
require 'aws-xray-sdk'

module DDLambda
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      attr_accessor :context

      def initialize
        XRay.recorder.configure(
          patch: %I[net_http aws_sdk],
          context: DDLambda::Trace::LambdaContext.new,
          streamer: DDLambda::Trace::LambdaStreamer.new,
          emitter: DDLambda::Trace::LambdaEmitter.new
        )
        puts 'Listener Initialized'
      end

      def on_start(event:)
        @context = DDLambda::Trace.extract_trace_context(event)
      rescue StandardError => e
        puts "couldn't read tracing context #{e}"
      end

      def on_end; end
    end
  end
end
