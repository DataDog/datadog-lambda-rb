# frozen_string_literal: true

require 'datadog/lambda'
require 'net/http'

Datadog::Lambda.configure_apm do |c|
end

def handle(event:, context:)
  Datadog::Lambda.wrap(event, context) do
    urls = ['ip-ranges.datadoghq.com', 'ip-ranges.datadoghq.eu']
    response_payload = {
      'message' => 'hello, dog!'
    }
    Datadog::Lambda.metric('serverless.integration_test.execution', 1, function: 'http-request')
    urls.each do |url|
      Net::HTTP.get_response(url, '/')
    end
    puts("Snapshot test http requests successfully made to URLs: #{urls}")
    response_payload
  end
end
