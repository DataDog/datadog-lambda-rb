# frozen_string_literal: true

require 'ddlambda/trace/context'

module DDLambda
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      attr_accessor :context

      def initialize
        puts 'Listener Initialized'
      end

      def on_start(event:)
        @context = DDLambda::Trace.extract_trace_context(event)
      end

      def on_end; end
    end
  end
end
