# frozen_string_literal: true

module Datadog
  module Lambda
    module AppSec
      # Normalizes API Gateway v1/v2 event payloads into a standard key set.
      module EventNormalizer
        module_function

        def normalize(event)
          event.key?('httpMethod') ? normalize_v1(event) : normalize_v2(event)
        end

        def normalize_v1(event)
          data = {
            'method' => event['httpMethod'],
            'path' => event['path'],
            'headers' => event['headers'],
            'query' => event['multiValueQueryStringParameters'] || event['queryStringParameters'],
            'source_ip' => event.dig('requestContext', 'identity', 'sourceIp'),
            'body' => event['body'],
            'base64_encoded' => event['isBase64Encoded'],
            'path_params' => event['pathParameters']
          }
          data.compact!
          data
        end

        def normalize_v2(event)
          data = {
            'method' => event.dig('requestContext', 'http', 'method'),
            'path' => event['rawPath'],
            'headers' => event['headers'],
            'cookies' => event['cookies'],
            'query' => event['queryStringParameters'],
            'query_string' => event['rawQueryString'],
            'source_ip' => event.dig('requestContext', 'http', 'sourceIp'),
            'body' => event['body'],
            'base64_encoded' => event['isBase64Encoded'],
            'path_params' => event['pathParameters']
          }
          data.compact!
          data
        end
      end
    end
  end
end
