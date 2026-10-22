# frozen_string_literal: true

module Datadog
  module Lambda
    module AppSec
      # Normalizes Lambda handler return values into a standard key set.
      #
      # @see https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-output-format
      module ResponseNormalizer
        module_function

        def normalize(response)
          data = {
            'status_code' => response['statusCode'],
            'headers' => merge_headers(response),
            'body' => response['body'],
            'base64_encoded' => response['isBase64Encoded']
          }
          data.compact!
          data
        end

        # Merges single-value and multi-value headers into one hash with
        # multi-value entries take priority when a key appears in both.
        def merge_headers(response)
          headers = response['headers']
          multi_headers = response['multiValueHeaders']

          return headers unless multi_headers
          return multi_headers unless headers

          headers.merge(multi_headers)
        end
      end
    end
  end
end
