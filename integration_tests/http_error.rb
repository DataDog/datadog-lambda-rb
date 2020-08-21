# frozen_string_literal: true

require 'datadog/lambda'
require 'net/http'

Datadog::Lambda.configure_apm do |c|
end

def handle(event:, context:)
  Datadog::Lambda.wrap(event, context) do
    response_payload = {
      'message' => 'hello, dog!'
    }
    Datadog::Lambda.metric('serverless.integration_test.execution', 1, function: 'http-request')

    Net::HTTP.get_response('httpstat.us', '/400')

    puts('Snapshot test http requests successfully made to URLs: https://httpstat.us/400')
    response_payload
  end
end
