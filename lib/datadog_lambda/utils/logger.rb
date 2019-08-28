# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

require 'logger'

module Datadog
  # Utils contains utility functions shared between modules
  module Utils
    def self.logger
      @logger ||= Logger.new(STDOUT)
    end

    def self.update_log_level
      log_level = (ENV['DD_LOG_LEVEL'] || 'error').downcase
      logger.level = case log_level
                     when 'debug'
                       Logger::DEBUG
                     when 'info'
                       Logger::INFO
                     when 'warn'
                       Logger::WARN
                     else
                       Logger::ERROR
                     end
    end
  end
end
