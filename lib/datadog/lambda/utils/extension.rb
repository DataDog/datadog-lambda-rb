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
    # PROPAGATOR = Tracing::Distributed::Propagation.new(propagation_styles: {
    #   Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG =>
    #     Tracing::Distributed::Datadog.new(fetcher: Tracing::Contrib::HTTP::Distributed::Fetcher)
    # })

    PROPAGATOR = Tracing::Distributed::Datadog.new(
      fetcher: Tracing::Contrib::HTTP::Distributed::Fetcher
    )

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
      Datadog::Utils.logger.debug "[start] received event is #{event.to_json}"
      Datadog::Utils.logger.debug "[start] response returned #{response.inspect}"

      trace_digest = PROPAGATOR.extract(response)
      Datadog::Utils.logger.debug "[start] extracted trace digest #{trace_digest.inspect}"

      trace_digest
    rescue StandardError => e
      Datadog::Utils.logger.debug "failed on start invocation request to extension: #{e} #{e.backtrace}"
    end

    def self.send_end_invocation_request(response:)
      return unless extension_running?

      request = Net::HTTP::Post.new(END_INVOCATION_URI)
      request.body = response.to_json
      request[Datadog::Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST] = 1

      trace_digest = Datadog::Tracing.active_trace&.to_digest
      Datadog::Utils.logger.debug "[end] current trace_digest #{trace_digest.inspect} to inject"

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
