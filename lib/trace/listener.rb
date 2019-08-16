# frozen_string_literal: true

module Datadog
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      def initialize
        puts 'Listener Initialized'
      end

      def on_start(event:, context:)
        puts 'Listener On Start Called'
        context
      end

      def on_end
        puts 'Listener On End Called'
      end
    end
  end
end
