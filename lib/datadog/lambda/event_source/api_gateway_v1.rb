# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2026 Datadog, Inc.
#

module Datadog
  module Lambda
    module EventSource
      # Parses API Gateway REST API (v1) Lambda proxy integration events
      # into a uniform interface.
      #
      # @see https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
      class ApiGatewayV1
        class << self
          def match?(payload)
            api_gateway?(payload) && payload.key?('httpMethod')
          end

          private

          def api_gateway?(payload)
            payload.is_a?(Hash) &&
              payload.key?('requestContext') && payload['requestContext'].key?('stage')
          end
        end

        def initialize(payload)
          @payload = payload
          @request_context = payload.fetch('requestContext', {})
        end

        def method = @payload['httpMethod']
        def path = @payload.fetch('path', '/')
        def resource_path = @request_context.fetch('resourcePath', path)
        def domain = @request_context['domainName']
        def api_id = @request_context['apiId']
        def stage = @request_context['stage']
        def request_time_ms = @request_context['requestTimeEpoch']
        def user_agent = @request_context.dig('identity', 'userAgent')
      end
    end
  end
end
