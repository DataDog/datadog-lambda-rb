# frozen_string_literal: true

# `ddtrace`` is an optional dependency for the ruby package
begin
  require 'ddtrace'
rescue LoadError
  Datadog::Utils.logger.debug 'dd-trace unavailable'
end

module Datadog
  # TraceListener tracks tracing context information
  module Trace
    class <<self
      def apply_datadog_trace_context(context)
        unless context.nil?
          trace_id = context[:trace_id].to_i
          span_id = context[:parent_id].to_i
          sampling_priority = context[:sample_mode]
          trace_digest = Datadog::Tracing::TraceDigest.new(
            span_id: span_id,
            trace_id: trace_id,
            trace_sampling_priority: sampling_priority
          )
          Datadog::Tracing.continue_trace!(trace_digest)
        end
      rescue StandardError
        Datadog::Utils.logger.debug 'dd-trace unavailable'
      end

      def wrap_datadog(options, &block)
        tracer_available = false
        begin
          raise StandardError unless Datadog::Tracing.enabled?

          tracer_available = true
        rescue StandardError
          Datadog::Utils.logger.debug 'dd-trace unavailable'
        end
        return block.call unless tracer_available

        Datadog::Tracing.trace('aws.lambda', options) do |_span|
          block.call
        end
      end
    end
  end
end
