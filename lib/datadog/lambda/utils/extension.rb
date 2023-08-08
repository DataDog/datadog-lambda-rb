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
      return unless extension_running?

      response = Net::HTTP.post(START_INVOCATION_URI, event.to_json)
      _update_trace_context_on_response_headers(response: response)
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on start invocation request to extension: #{e}"
    end

    def self._update_trace_context_on_response_headers(response:)
      trace_context = {}
      trace_context[:trace_id] &&= response[Datadog::Trace::DD_TRACE_ID_HEADER]
      trace_context[:parent_id] &&= response[Datadog::Trace::DD_PARENT_ID_HEADER]
      trace_context[:sample_mode] &&= response[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER]

      return if trace_context.empty?

      Datadog::Utils.logger.debug "trace context will be updated to #{trace_context.to_json}"
      Datadog::Trace.apply_datadog_trace_context(trace_context)
    end

    def self.send_end_invocation_request(response:)
      return unless extension_running?

      trace_context = Datadog::Trace.trace_context
      Datadog::Utils.logger.debug "current trace context is #{trace_context} #{trace_context.to_json}"
      headers = trace_context_to_headers(trace_context)
      Datadog::Utils.logger.debug "headers are #{headers} #{headers.to_json}"

      Net::HTTP.post(END_INVOCATION_URI, response.to_json, headers)
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on end invocation request to extension: #{e}"
    end

    def self.trace_context_to_headers(trace_context)
      headers = {}

      return active_span_trace_context_to_headers(headers) if trace_context.nil?

      headers[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym] = trace_context[:trace_id]
      headers[Datadog::Trace::DD_SPAN_ID_HEADER.to_sym] = trace_context[:span_id]
      headers[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER.to_sym] = trace_context[:sample_mode]

      headers
    end

    def self.active_span_trace_context_to_headers(headers)
      headers[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym] = Datadog::Tracing.active_span.trace_id.to_s
      headers[Datadog::Trace::DD_SPAN_ID_HEADER.to_sym] = Datadog::Tracing.active_span.id.to_s
      headers
    end
  end
end
