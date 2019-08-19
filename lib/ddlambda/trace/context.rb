# frozen_string_literal: true

require 'ddlambda/trace/constants'

module DDLambda
  module Trace
    def self.read_trace_context_from_event(event)
      return nil unless event.is_a?(Hash)
      return nil unless event.key?('headers') && event['headers'].is_a?(Hash)

      headers = event['headers'].transform_keys(&:downcase)
      return nil unless headers.key?(DD_TRACE_ID_HEADER) && headers[DD_TRACE_ID_HEADER].is_a?(String)
      return nil unless headers.key?(DD_PARENT_ID_HEADER) && headers[DD_PARENT_ID_HEADER].is_a?(String)
      return nil unless headers.key?(DD_SAMPLING_PRIORITY_HEADER) && headers[DD_SAMPLING_PRIORITY_HEADER].is_a?(String)

      {
        trace_id: headers[DD_TRACE_ID_HEADER],
        parent_id: headers[DD_PARENT_ID_HEADER],
        sample_mode: headers[DD_SAMPLING_PRIORITY_HEADER].to_i
      }
    end

    def self.convert_to_apm_trace_id(xray_trace_id)
      parts = xray_trace_id.split('-')
      return nil if parts.length < 3

      last_part = parts[2]
      return nil if last_part.length != 24
      # Make sure every character is hex
      return nil if last_part.upcase[/\H/]

      hex = last_part.to_i(16)
      last_63_bits = hex & 0x7fffffffffffffff
      last_63_bits.to_s(10)
    end

    def self.convert_to_apm_parent_id(xray_parent_id)
      return nil if xray_parent_id.length != 16
      return nil if xray_parent_id.upcase[/\H/]

      hex = xray_parent_id.to_i(16)
      hex.to_s(10)
    end

    def self.convert_to_sample_mode(xray_sampled)
      xray_sampled == '1' ? SAMPLE_MODE_USER_KEEP : SAMPLE_MODE_USER_REJECT
    end
  end
end
