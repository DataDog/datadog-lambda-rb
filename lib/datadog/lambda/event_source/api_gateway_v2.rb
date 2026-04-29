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
      # Parses API Gateway HTTP API (v2) Lambda proxy integration events
      # into a uniform interface.
      #
      # @see https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#http-api-develop-integrations-lambda.proxy-format
      class ApiGatewayV2
        class << self
          def match?(payload)
            api_gateway?(payload) && payload.key?('routeKey')
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
          @http = @request_context.fetch('http', {})
        end

        def method = @http['method']
        def path = @payload.fetch('rawPath', '/')
        def resource_path = @payload['routeKey']&.sub(/\A[A-Z]+ /, '') || path
        def domain = @request_context['domainName']
        def api_id = @request_context['apiId']
        def stage = @request_context['stage']
        def request_time_ms = @request_context['timeEpoch']
        def user_agent = @http['userAgent']
      end
    end
  end
end
