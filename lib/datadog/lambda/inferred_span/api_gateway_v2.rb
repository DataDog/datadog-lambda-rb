# frozen_string_literal: true

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2026 Datadog, Inc.

require 'forwardable'

module Datadog
  module Lambda
    module InferredSpan
      # Wraps EventSource::ApiGatewayV2 with additional span-specific attributes.
      class ApiGatewayV2
        extend Forwardable

        def_delegators :@event_source,
                       :method, :path, :resource_path, :domain,
                       :api_id, :stage, :request_time_ms, :user_agent,
                       :http_url

        def initialize(event_source)
          @event_source = event_source
        end

        def span_name = 'aws.httpapi'
        def arn_path_prefix = 'apis'
      end
    end
  end
end
