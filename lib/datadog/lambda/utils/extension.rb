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
    AGENT_URL = 'http://127.0.0.1:8124'
    HELLO_PATH = '/lambda/hello'
    EXTENSION_CHECK_URI = URI(AGENT_URL + HELLO_PATH).freeze
    EXTENSION_PATH = '/opt/extensions/datadog-agent'

    @is_extension_running = nil

    def self.extension_running?
      return @is_extension_running unless @is_extension_running.nil?

      @is_extension_running = check_extension_running

      @is_extension_running
    end

    def self.check_extension_running
      return false unless File.exist?(EXTENSION_PATH)

      begin
        Net::HTTP.get(EXTENSION_CHECK_URI)
      rescue StandardError => e
        Datadog::Utils.logger.debug "extension is not running, returned with error #{e}"
        return false
      end

      true
    end
  end
end
