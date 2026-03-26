# frozen_string_literal: true

module Datadog
  module Lambda
    module InferredSpan
      # Parses API Gateway REST API (v1) Lambda proxy integration events
      # into a uniform interface.
      #
      # @see https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
      class ApiGatewayV1
        def self.match?(payload)
          api_gateway?(payload) && payload.key?('httpMethod')
        end

        private_class_method def self.api_gateway?(payload)
          payload.is_a?(Hash) &&
            payload.key?('requestContext') && payload['requestContext'].key?('stage')
        end

        def initialize(payload)
          @payload = payload
          @request_context = payload.fetch('requestContext', {})
        end

        def span_name = 'aws.apigateway'
        def method = @payload['httpMethod']
        def path = @payload.fetch('path', '/')
        def resource_path = @request_context.fetch('resourcePath', path)
        def domain = @request_context.fetch('domainName', '')
        def api_id = @request_context.fetch('apiId', '')
        def stage = @request_context.fetch('stage', '')
        def request_time_ms = @request_context['requestTimeEpoch']
        def user_agent = @request_context.dig('identity', 'userAgent')
        def arn_path_prefix = 'restapis'
      end
    end
  end
end
