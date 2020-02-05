# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#
require 'datadog/lambda/trace/constants'
require 'datadog/lambda/utils/logger'
require 'securerandom'
require 'json'
require 'socket'

module Datadog
  # Trace contains utilities related to reading/writing trace context from
  # lambda events/X-Ray
  module Trace
    class << self
      def read_trace_context_from_xray
        header = ENV[XRAY_ENV_VAR]
        segment = parse_xray_trace_context_header(header)
        trace_id = convert_to_apm_trace_id(segment[:xray_trace_id])
        parent_id = convert_to_apm_parent_id(segment[:xray_parent_id])
        sample_mode = convert_to_sample_mode(segment[:xray_sample_mode])

        if trace_id.nil? || parent_id.nil? || sample_mode.nil?
          Datadog::Utils.logger.error("couldn't read xray trace header #{header}")
          return nil
        end
        {
          trace_id: trace_id,
          parent_id: parent_id,
          sample_mode: sample_mode,
          source: SOURCE_XRAY
        }
      end

      def add_trace_context_to_xray(context)
        data = generate_xray_metadata_subsegment(context)
        send_xray_daemon_data(data)
        Datadog::Utils.logger.debug("sent metadata to xray #{data}")
      end

      def generate_xray_metadata_subsegment(context)
        time = Time.now.to_f
        header = ENV[XRAY_ENV_VAR]
        segment = parse_xray_trace_context_header(header)

        {
          "id": SecureRandom.hex(8),
          "trace_id": segment[:xray_trace_id],
          "parent_id": segment[:xray_parent_id],
          "name": DD_XRAY_SUBSEGMENT_NAME,
          "start_time": time,
          "end_time": time,
          "type": 'subsegment',
          "metadata": {
            "datadog": {
              "trace": {
                "parent-id": context[:parent_id],
                "sampling-priority": context[:sample_mode].to_s,
                "trace-id": context[:trace_id]
              }
            }
          }
        }.to_json
      end

      def current_trace_context(trace_context)
        trace_context = Hash[trace_context]
        begin
          # This will only succeed if the user has imported xray themselves
          entity = XRay.recorder.current_entity
          trace_context[:parent_id] = convert_to_apm_parent_id(entity.id)
        rescue StandardError
          Datadog::Utils.logger.debug("couldn't fetch xray entity")
        end
        trace_context
      end

      def send_xray_daemon_data(data)
        xray_daemon_env = ENV[AWS_XRAY_DAEMON_ADDRESS_ENV_VAR]
        socket = XRAY_UDP_PORT
        address = LOCAL_HOST
        address, socket = xray_daemon_env.split(':') unless xray_daemon_env.nil?

        sock = UDPSocket.open
        message = "{\"format\": \"json\", \"version\": 1}\n#{data}"
        sock.send(message, 0, address, socket)
      end

      def parse_xray_trace_context_header(header)
        Datadog::Utils.logger.error("Reading trace context from env #{header}")
        root, parent, sampled = header.split(';')

        trace_id = parse_assigned_value(root)
        parent_id = parse_assigned_value(parent)
        sample_mode = parse_assigned_value(sampled)

        return nil if trace_id.nil? || parent_id.nil? || sample_mode. nil?

        {
          xray_trace_id: trace_id,
          xray_parent_id: parent_id,
          xray_sample_mode: sample_mode
        }
      end

      def parse_assigned_value(value)
        return nil if value.nil?

        _, raw_value, * = value.split('=')
        raw_value
      end

      def convert_to_apm_trace_id(xray_trace_id)
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

      def convert_to_apm_parent_id(xray_parent_id)
        return nil if xray_parent_id.length != 16
        return nil if xray_parent_id.upcase[/\H/]

        hex = xray_parent_id.to_i(16)
        hex.to_s(10)
      end

      def convert_to_sample_mode(xray_sampled)
        xray_sampled == '1' ? SAMPLE_MODE_USER_KEEP : SAMPLE_MODE_USER_REJECT
      end
    end
  end
end
