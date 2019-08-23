# frozen_string_literal: true

require 'aws-xray-sdk'
require 'ddlambda/trace/constants'

module DDLambda
  # Trace contains utilities related to reading/writing trace context from
  # lambda events/X-Ray
  module Trace
    def self.extract_trace_context(event)
      context = read_trace_context_from_event(event)
      if context
        begin
          add_trace_context_to_xray(context)
        rescue StandardError => e
          puts "couldn't add metadata to xray #{e}"
        end
        return context
      end
      read_trace_context_from_xray
    end

    def self.add_trace_context_to_xray(context)
      seg = XRay.recorder.begin_subsegment(
        name: DD_XRAY_SUBSEGMENT_NAME,
        namespace: DD_XRAY_SUBSEGMENT_NAMESPACE
      )
      seg.metadata[DD_XRAY_SUBSEGMENT_KEY] = {
        "trace-id": context[:trace_id],
        "parent-id": context[:parent_id],
        "sampling-priority": context[:sample_mode].to_s
      }

      XRay.recorder.end_subsegment
    end

    def self.read_trace_context_from_xray
      segment = XRay.recorder.current_segment
      parent_id = segment.instance_variable_get('@parent_id')
      mode = segment.sampled ? SAMPLE_MODE_USER_KEEP : SAMPLE_MODE_USER_REJECT
      {
        trace_id: convert_to_apm_trace_id(segment.trace_id),
        parent_id: convert_to_apm_parent_id(parent_id),
        sample_mode: mode
      }
    rescue StandardError => e
      puts "couldn't read xray trace header #{e}"
      nil
    end

    def self.read_trace_context_from_event(event)
      return nil unless headers?(event)

      headers = event['headers'].transform_keys(&:downcase)
      return nil unless trace_headers_present?(headers)

      {
        trace_id: headers[DD_TRACE_ID_HEADER],
        parent_id: headers[DD_PARENT_ID_HEADER],
        sample_mode: headers[DD_SAMPLING_PRIORITY_HEADER].to_i
      }
    end

    def self.headers?(event)
      event.is_a?(Hash) && event.key?('headers') && event['headers'].is_a?(Hash)
    end

    def self.trace_headers_present?(headers)
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
