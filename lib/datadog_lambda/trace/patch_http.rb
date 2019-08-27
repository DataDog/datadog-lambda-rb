# frozen_string_literal: true

require 'net/http'

module Datadog
  # Trace contains methods to help with patching Net/HTTP
  module Trace
    def self.trace_context
      @trace_context
    end

    def self.trace_context=(val)
      @trace_context = val
    end

    @patched = false
    def self.patch_http
      Net::HTTP.prepend NetExtensions unless @patched
      @patched = true
    end

    # NetExtensions contains patches which add tracing context to http calls
    module NetExtensions
      def request(req, body = nil, &block)
        logger = Datadog::Utils.logger
        begin
          context = Datadog::Trace.current_trace_context(
            Datadog::Trace.trace_context
          )

          req[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER.to_sym] =
            context[:sample_mode]
          req[Datadog::Trace::DD_PARENT_ID_HEADER.to_sym] = context[:parent_id]
          req[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym] = context[:trace_id]
          logger.debug("added context #{context} to request")
        rescue StandardError => e
          logger.error(
            "couldn't add tracing context #{context} to request #{e}"
          )
        end
        super(req, body, &block)
      end
    end
  end
end
