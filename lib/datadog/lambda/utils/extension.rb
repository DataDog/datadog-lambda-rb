# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2023 Datadog, Inc.
#
require 'net/http'

module Datadog
  # Utils contains utility functions shared between modules
  module Utils
    EXTENSION_PATH = '/opt/extensions/datadog-agent'
    EXTENSION_BASE_URL = 'http://127.0.0.1:8124'

    START_INVOCATION_PATH = '/lambda/start-invocation'
    END_INVOCATION_PATH = '/lambda/end-invocation'

    START_INVOCATION_URI = URI(AGENT_URL + START_INVOCATION_PATH).freeze
    END_INVOCATION_URI = URI(AGENT_URL + END_INVOCATION_PATH).freeze

    def self.extension_running
      File.exist?(EXTENSION_PATH)
    end

    def self.send_start_invocation_request(event:)
      begin
        response = Net::HTTP.post(START_INVOCATION_URI, event.to_json)
        puts "response: #{response.body}"
        puts "headers: #{response} #{response.inspect}"
        _update_trace_context_on_response_headers(response: response)
      rescue StandardError => e
        puts "[error][start] #{e}"
      end
    end

    def self.send_end_invocation_request(response:)
      begin
        headers = _end_invocation_request_headers
        result = Net::HTTP.post(END_INVOCATION_URI, response.to_json, headers)
        puts "response: #{result.body}"
        puts "headers: #{headers} #{headers.inspect}"
      rescue StandardError => e
        puts "[error][end] #{e}"
      end
    end

    # rubocop:disable Metrics/AbcSize
    def self._end_invocation_request_headers
      headers = {}
      headers[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym] = Datadog::Tracing.active_span.trace_id.to_s
      headers[Datadog::Trace::DD_SPAN_ID_HEADER.to_sym] = Datadog::Tracing.active_span.id.to_s
      headers[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER.to_sym] = '1'

      headers
    end

    def self._update_trace_context_on_response_headers(response:)
      trace_context = {}

      trace_context[:trace_id] &&= response[DD_TRACE_ID_HEADER]
      trace_context[:parent_id] &&= response[DD_PARENT_ID_HEADER]
      trace_context[:sample_mode] &&= response[DD_SAMPLING_PRIORITY_HEADER]
      puts "modifying context: #{trace_context} whereas context from module is: #{Datadog::Trace.trace_context}"
      Datadog::Trace.trace_context = trace_context unless trace_context.empty?
    end
  end
end

# rubocop:enable Metrics/AbcSize
