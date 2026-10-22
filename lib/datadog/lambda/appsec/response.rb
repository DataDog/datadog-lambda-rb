# frozen_string_literal: true

module Datadog
  module Lambda
    module AppSec
      # Minimal response object for AppSec event recording.
      #
      # WARNING: It's a minimal data for interface compliance
      #
      # @see Datadog::AppSec::APISecurity.sample?
      # @see Datadog::AppSec::Contrib::Rack::Gateway::Response
      class Response
        attr_reader :status, :headers, :body

        def self.from_normalized(normalized)
          new(
            status: normalized['status_code'].to_i,
            headers: normalized['headers'] || {},
            body: normalized['body']
          )
        end

        def initialize(status:, headers:, body:)
          @status = status
          @headers = headers
          @body = body
        end
      end
    end
  end
end
