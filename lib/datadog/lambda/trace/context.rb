# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

require 'datadog/lambda/trace/constants'
require 'datadog/lambda/trace/xray'
require 'datadog/lambda/utils/logger'

module Datadog
  # Trace contains utilities related to reading/writing trace context from
  # lambda events/X-Ray
  module Trace
    class << self
      def trace_context_to_headers(trace_context)
        headers = {}

        headers[DD_TRACE_ID_HEADER.to_sym] = trace_context[:trace_id]
        headers[DD_SPAN_ID_HEADER.to_sym] = trace_context[:span_id]
        headers[DD_SAMPLING_PRIORITY_HEADER.to_sym] = trace_context[:sample_mode]

        headers
      end

      def extract_trace_context(event, merge_xray_traces)
        context = read_trace_context_from_event(event)
        unless context.nil?
          begin
            add_trace_context_to_xray(context)
          rescue StandardError => e
            Datadog::Utils.logger.debug("couldn't add metadata to xray #{e}")
          end
          return context
        end
        return nil unless merge_xray_traces

        read_trace_context_from_xray
      end

      def read_trace_context_from_event(event)
        return nil unless headers?(event)

        headers = event['headers'].transform_keys(&:downcase)

        return nil unless trace_headers_present?(headers)

        {
          trace_id: headers[DD_TRACE_ID_HEADER],
          parent_id: headers[DD_PARENT_ID_HEADER],
          sample_mode: headers[DD_SAMPLING_PRIORITY_HEADER].to_i,
          source: SOURCE_EVENT
        }
      end

      def headers?(event)
        event.is_a?(Hash) && event.key?('headers') &&
          event['headers'].is_a?(Hash)
      end

      def trace_headers_present?(headers)
        expected = [
          DD_TRACE_ID_HEADER,
          DD_PARENT_ID_HEADER,
          DD_SAMPLING_PRIORITY_HEADER
        ]
        expected.each do |key|
          return false unless headers.key?(key) && headers[key].is_a?(String)
        end
        true
      end
    end
  end
end
