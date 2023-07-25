# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2023 Datadog, Inc.
#

require 'datadog/statsd'

module Datadog
  # Metrics module contains the singleton class Client to send custom
  # metrics to Datadog.
  module Metrics
    URL = 'localhost'
    PORT = '8125'
    class << self
      @instance = new

      private_class_method :new

      def self.distribution(name, value, time: nil, **tags)
        tag_list = get_tags(**tags)

        if Datadog::Utils.extension_running?
          @instance.distribution(name, value, tags: tag_list)
        else
          time ||= Time.now
          time_ms = time.to_f.to_i

          metric = { e: time_ms, m: name, t: tag_list, v: value }
          puts metric.to_json
        end
      end

      def self.end
        @instance&.close
      end

      def get_tags(**tags)
        tag_list = ["dd_lambda_layer:datadog-ruby#{dd_lambda_layer_tag}"]
        tags.each do |tag|
          tag_list.push("#{tag[0]}:#{tag[1]}")
        end

        tag_list
      end

      def initialize
        @instance = Datadog::Statsd.new(URL, PORT, single_thread: true) if Datadog::Utils.extension_running?
      end
    end
  end
end
