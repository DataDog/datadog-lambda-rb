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

      response = Net::HTTP.post(START_INVOCATION_URI, event.to_json, request_headers)
      # update_trace_context_on_response(response: response)

      p ' --- [layer][start] response is'
      p response.each_header.to_h

      trace_digest = Tracing::Propagation::HTTP.extract(response)
      p ' --- [layer][start] trace digest is'
      p trace_digest.inspect
      Tracing.continue_trace!(trace_digest) if trace_digest
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on start invocation request to extension: #{e}"
    end

    def self.update_trace_context_on_response(response:)
      trace_context = headers_to_trace_context(response)

      return if trace_context.empty?

      Datadog::Utils.logger.debug "trace context will be updated to #{trace_context.to_json}"
      Datadog::Trace.apply_datadog_trace_context(trace_context)
    end

    def self.headers_to_trace_context(headers)
      trace_context = {}

      trace_id = headers[Datadog::Trace::DD_TRACE_ID_HEADER]
      parent_id = headers[Datadog::Trace::DD_PARENT_ID_HEADER]
      sample_mode = headers[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER]

      trace_context[:trace_id] = trace_id unless trace_id.nil?
      trace_context[:parent_id] = parent_id unless parent_id.nil?
      trace_context[:sample_mode] = sample_mode unless sample_mode.nil?

      trace_context
    end

    def self.send_end_invocation_request(response:)
      return unless extension_running?

      # trace_context = Datadog::Trace.trace_context
      # Datadog::Utils.logger.debug "current trace context is #{trace_context} #{trace_context.to_json}"
      # headers = trace_context.nil? ? active_trace_context_to_headers : trace_context_to_headers(trace_context)
      # Datadog::Utils.logger.debug "headers are #{headers} #{headers.to_json}"

      # Net::HTTP.post(END_INVOCATION_URI, response.to_json, headers)

      request = Net::HTTP::Post.new(END_INVOCATION_URI)
      request.body = response.to_json
      request['DD-Internal-Untraced-Request'] = 'true'

      trace = Datadog::Tracing.active_trace
      p ' --- [layer][end] BEFORE INJECTION trace digest is'
      p trace&.to_digest.inspect
      Tracing::Propagation::HTTP.inject!(trace, request)
      p ' --- [layer][end] AFTER INJECTION trace digest is'
      p trace&.to_digest.inspect
      Net::HTTP.start(END_INVOCATION_URI.host, END_INVOCATION_URI.port) do |http|
        p ' --- [layer][end] request is'
        p request.each_header.to_h

        http.request(request)
      end
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on end invocation request to extension: #{e}"
    end

    def self.trace_context_to_headers(trace_context)
      headers = request_headers

      return if trace_context.nil?

      headers[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym] = trace_context[:trace_id].to_s
      headers[Datadog::Trace::DD_PARENT_ID_HEADER.to_sym] = trace_context[:parent_id].to_s
      headers[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER.to_sym] = trace_context[:sample_mode].to_s

      headers
    end

    def self.active_trace_context_to_headers
      headers = request_headers

      trace_digest = Datadog::Tracing.active_trace.to_digest
      headers[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym] = trace_digest.trace_id.to_s
      headers[Datadog::Trace::DD_PARENT_ID_HEADER.to_sym] = trace_digest.span_id.to_s
      headers[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER.to_sym] = trace_digest.trace_sampling_priority.to_s

      headers
    end

    def self.request_headers
      {
        Datadog::Trace::HEADER_DD_INTERNAL_UNTRACED_REQUEST.to_sym => 'true'
      }
    end
  end
end
