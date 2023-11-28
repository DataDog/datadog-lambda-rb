# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2023 Datadog, Inc.
#
require 'net/http'
require 'datadog/tracing/contrib/http/distributed/fetcher'

module Datadog
  # Utils contains utility functions shared between modules
  module Utils
    EXTENSION_PATH = '/opt/extensions/datadog-agent'
    EXTENSION_BASE_URL = 'http://127.0.0.1:8124'

    START_INVOCATION_PATH = '/lambda/start-invocation'
    END_INVOCATION_PATH = '/lambda/end-invocation'

    START_INVOCATION_URI = URI(EXTENSION_BASE_URL + START_INVOCATION_PATH).freeze
    END_INVOCATION_URI = URI(EXTENSION_BASE_URL + END_INVOCATION_PATH).freeze

    # Internal communications use Datadog tracing headers
    PROPAGATOR = Tracing::Distributed::Datadog.new(fetcher: Tracing::Contrib::HTTP::Distributed::Fetcher)

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
      trace_digest = PROPAGATOR.extract(response)

      # Only continue trace from a new one if it exist, or else,
      # it will create a new trace, which is not ideal here.
      current_trace = Datadog::Tracing.active_trace
      Datadog::Utils.logger.debug "[start] current active trace #{current_trace}"
      _trace_digest = current_trace&.to_digest
      Datadog::Utils.logger.debug "[start] current trace digest #{_trace_digest&.trace_id} #{_trace_digest&.span_id} #{_trace_digest&.span_name}"
      if trace_digest
        Datadog::Utils.logger.debug "[start] found a trace context #{trace_digest} continuing trace with it"
        Datadog::Utils.logger.debug "[start] new trace digest #{_trace_digest&.trace_id} #{_trace_digest&.span_id} #{_trace_digest&.span_name}"
      end

      trace_digest
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on start invocation request to extension: #{e}"
    end

    def self.send_end_invocation_request(response:)
      return unless extension_running?

      request = Net::HTTP::Post.new(END_INVOCATION_URI)
      request.body = response.to_json
      request[Datadog::Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST] = 1

      trace_digest = Datadog::Tracing.active_trace&.to_digest
      Datadog::Utils.logger.debug "[end] current trace digest #{trace_digest&.trace_id} #{trace_digest&.span_id} #{trace_digest&.span_name}" if trace_digest
      PROPAGATOR.inject!(trace_digest, request)
      Net::HTTP.start(END_INVOCATION_URI.host, END_INVOCATION_URI.port) do |http|
        http.request(request)
      end
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on end invocation request to extension: #{e}"
    end

    def self.request_headers
      {
        # Header used to avoid tracing requests that are internal to
        # Datadog products.
        Datadog::Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST.to_sym => 'true'
      }
    end
  end
end
