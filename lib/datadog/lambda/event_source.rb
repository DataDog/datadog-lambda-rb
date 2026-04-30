# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2026 Datadog, Inc.
#

require_relative 'event_source/api_gateway_v1'
require_relative 'event_source/api_gateway_v2'

module Datadog
  module Lambda
    # Detects and parses Lambda event payloads into a uniform interface.
    module EventSource
      SOURCES = [ApiGatewayV1, ApiGatewayV2].freeze

      def self.for(event)
        klass = SOURCES.find { |source| source.match?(event) }
        klass&.new(event)
      end
    end
  end
end
