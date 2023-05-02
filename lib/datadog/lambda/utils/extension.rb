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
    EXTENSION_PATH = '/opt/extensions/datadog-agent'

    def self.extension_running
      return false unless File.exist?(EXTENSION_PATH)

      begin
        Net::HTTP.get(URI(AGENT_URL + HELLO_PATH))
      rescue StandardError => e
        Datadog::Utils.logger.debug "extension is not running, returned with error #{e}"
        return false
      end

      true
    end
  end
end
