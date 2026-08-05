# frozen_string_literal: true

module Datadog
  module Lambda
    module AppSec
      # Minimal request object for AppSec event recording.
      #
      # WARNING: It's a minimal data for interface compliance
      #
      # @see Datadog::AppSec::Event.record
      # @see Datadog::AppSec::Contrib::Rack::Gateway::Request
      class Request
        attr_reader :host, :user_agent, :remote_addr, :headers,
                    :request_method, :path

        class << self
          def from_normalized(event)
            new(
              remote_addr: event['source_ip'],
              headers: lowercase_headers(event),
              request_method: event['method'],
              path: event['path']
            )
          end

          private

          def lowercase_headers(event)
            (event['headers'] || {}).each_with_object({}) do |(key, value), hash|
              hash[key.downcase] = value
            end
          end
        end

        def initialize(remote_addr:, headers:, request_method:, path:)
          @headers = headers
          @host = headers['host']
          @user_agent = headers['user-agent']
          @remote_addr = remote_addr
          @request_method = request_method
          @path = path
        end
      end
    end
  end
end
