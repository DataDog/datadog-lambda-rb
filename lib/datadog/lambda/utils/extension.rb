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

    START_INVOCATION_URI = URI(EXTENSION_BASE_URL + START_INVOCATION_PATH).freeze
    END_INVOCATION_URI = URI(EXTENSION_BASE_URL + END_INVOCATION_PATH).freeze

    def self.extension_running?
      return @is_extension_running unless @is_extension_running.nil?

      @is_extension_running = check_extension_running
    end

    def self.check_extension_running
      File.exist?(EXTENSION_PATH)
    end

    def self.send_start_invocation_request(event:)
      response = Net::HTTP.post(START_INVOCATION_URI, event.to_json)
      _update_trace_context_on_response_headers(response: response)
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on start invocation request to extension: #{e}"
    end

    def self._update_trace_context_on_response_headers(response:)
      trace_context = {}
      trace_context[:trace_id] &&= response[DD_TRACE_ID_HEADER]
      trace_context[:parent_id] &&= response[DD_PARENT_ID_HEADER]
      trace_context[:sample_mode] &&= response[DD_SAMPLING_PRIORITY_HEADER]

      return if trace_context.empty?

      Datadog::Utils.logger.debug "trace context will be updated to #{trace_context.to_json}"
      Datadog::Trace.apply_datadog_trace_context(trace_context)
    end

    def self.send_end_invocation_request(response:)
      Datadog::Utils.logger.debug "current trace context is #{Datadog::Trace.trace_context} #{Datadog::Trace.trace_context.inspect}"
      headers = Datadog::Trace.trace_context_to_headers(Datadog::Trace.trace_context)

      result = Net::HTTP.post(END_INVOCATION_URI, response.to_json, headers)
      puts "response: #{result.body}"
      puts "headers: #{headers} #{headers.inspect}"
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on end invocation request to extension: #{e}"
    end
  end
end
