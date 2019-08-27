# frozen_string_literal: true

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
