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
        attr_reader :host, :user_agent, :remote_addr, :headers, :request_method, :path

        class << self
          def from_normalized(event)
            headers = lowercase_headers(event)

            new(
              host: headers['host'],
              user_agent: headers['user-agent'],
              remote_addr: event['source_ip'],
              headers: headers,
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

        def initialize(host:, user_agent:, remote_addr:, headers:, request_method: nil, path: nil)
          @host = host
          @user_agent = user_agent
          @remote_addr = remote_addr
          @headers = headers
          @request_method = request_method
          @path = path
        end

        def env
          @env ||= { 'SCRIPT_NAME' => '', 'PATH_INFO' => @path.to_s }
        end
      end
    end
  end
end
