# frozen_string_literal: true

require 'datadog/lambda'

Datadog::Lambda.configure_apm do |c|
  c.appsec.enabled = true
end

def handle(event:, context:)
  Datadog::Lambda.wrap(event, context) do
    Datadog::Lambda.metric('serverless.integration_test.execution', 1, function: 'appsec-request')

    {
      'statusCode' => 200,
      'message' => 'hello, dog!',
      'eventType' => 'APIGateway'
    }
  end
end
