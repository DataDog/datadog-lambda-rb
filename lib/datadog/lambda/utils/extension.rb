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

      trace_digest = Tracing::Propagation::HTTP.extract(response)
      # Only continue trace from a new one if it exist, or else,
      # it will create a new trace, which is not ideal here.
      Tracing.continue_trace!(trace_digest) if trace_digest
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on start invocation request to extension: #{e}"
    end

    def self.send_end_invocation_request(response:)
      return unless extension_running?

      request = Net::HTTP::Post.new(END_INVOCATION_URI)
      request.body = response.to_json
      request[Datadog::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST] = 1

      trace = Datadog::Tracing.active_trace
      Tracing::Propagation::HTTP.inject!(trace, request)
      Net::HTTP.start(END_INVOCATION_URI.host, END_INVOCATION_URI.port) do |http|
        http.request(request)
      end
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on end invocation request to extension: #{e}"
    end

    def self.request_headers
      {
        Datadog::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST.to_sym => 'true'
      }
    end
  end
end
