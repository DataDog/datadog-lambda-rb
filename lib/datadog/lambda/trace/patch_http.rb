# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

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

          req = add_ctx_to_req(req, context)
        rescue StandardError => e
          trace = e.backtrace.join("\n ")
          logger.debug(
            "couldn't add tracing context #{context} to request #{e}:\n#{trace}"
          )
        end
        super(req, body, &block)
      end

      private

      def add_ctx_to_req(req, context)
        req[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER.to_sym] =
          context[:sample_mode]
        req[Datadog::Trace::DD_PARENT_ID_HEADER.to_sym] = context[:parent_id]
        req[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym] = context[:trace_id]
        logger.debug("added context #{context} to request")
      end
    end
  end
end
