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
        attr_reader :host, :user_agent, :remote_addr, :headers

        class << self
          def from_event(event)
            headers = normalize_headers(event)
            remote_addres = event.dig('requestContext', 'identity', 'sourceIp') ||
                            event.dig('requestContext', 'http', 'sourceIp')

            new(
              host: headers['host'],
              user_agent: headers['user-agent'],
              remote_addr: remote_addres,
              headers: headers
            )
          end

          private

          def normalize_headers(event)
            event.fetch('headers', {}).each_with_object({}) do |(key, value), hash|
              hash[key.downcase] = value
            end
          end
        end

        def initialize(host:, user_agent:, remote_addr:, headers:)
          @host = host
          @user_agent = user_agent
          @remote_addr = remote_addr
          @headers = headers
        end
      end
    end
  end
end
