#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

# frozen_string_literal: true

require 'aws-xray-sdk'
require 'datadog_lambda/trace/constants'
require 'datadog_lambda/utils/logger'

module Datadog
  # Trace contains utilities related to reading/writing trace context from
  # lambda events/X-Ray
  module Trace
    def self.extract_trace_context(event)
      context = read_trace_context_from_event(event)
      unless context.nil?
        begin
          add_trace_context_to_xray(context)
        rescue StandardError => e
          Datadog::Utils.logger.error("couldn't add metadata to xray #{e}")
        end
        return context
      end
      read_trace_context_from_xray
    end

    def self.add_trace_context_to_xray(context)
      seg = XRay.recorder.begin_subsegment(
        DD_XRAY_SUBSEGMENT_NAME,
        namespace: DD_XRAY_SUBSEGMENT_NAMESPACE
      )
      data = {
        "parent-id": context[:parent_id],
        "sampling-priority": context[:sample_mode].to_s,
        "trace-id": context[:trace_id]
      }
      seg.metadata(namespace: DD_XRAY_SUBSEGMENT_NAMESPACE)
         .update("#{DD_XRAY_SUBSEGMENT_KEY}": data)
      XRay.recorder.end_subsegment
    end

    def self.current_trace_context(trace_context)
      entity = XRay.recorder.current_entity
      parent_id = entity.instance_variable_get('@parent_id')
      {
        trace_id: trace_context[:trace_id],
        parent_id: convert_to_apm_parent_id(parent_id),
        sample_mode: trace_context[:sample_mode]
      }
    end

    def self.read_trace_context_from_xray
      segment = XRay.recorder.current_entity
      parent_id = segment.instance_variable_get('@parent_id')
      mode = segment.sampled ? SAMPLE_MODE_USER_KEEP : SAMPLE_MODE_USER_REJECT
      {
        trace_id: convert_to_apm_trace_id(segment.trace_id),
        parent_id: convert_to_apm_parent_id(parent_id),
        sample_mode: mode
      }
    rescue StandardError => e
      Datadog::Utils.logger.error("couldn't read xray trace header #{e}")
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
