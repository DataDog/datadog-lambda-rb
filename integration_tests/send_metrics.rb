# frozen_string_literal: true

require 'datadog/lambda'

Datadog::Lambda.configure_apm do |c|
end

def handle(event:, context:)
  Datadog::Lambda.wrap(event, context) do
    response_payload = {
      'message' => 'hello, dog!'
    }

    if event.key?('requestContext')
      response_payload['eventType'] = 'APIGateway'
      response_payload['requestId'] = event['requestContext']['requestId']
    end

    if event.key?('Records')
      response_payload['recordIds'] = []
      event['Records'].each do |record|
        if record['messageId']
          response_payload['eventType'] = 'SQS'
          response_payload['recordIds'].push(record['messageId'])
          Datadog::Lambda.metric(
            'serverless.integration_test.records_processed',
            1,
            tagkey: 'tagvalue',
            eventsource: response_payload['eventType']
          )
        end
        next unless record['Sns']

        response_payload['eventType'] = 'SNS'
        response_payload['recordIds'].push(record['Sns']['MessageId'])
        Datadog::Lambda.metric(
          'serverless.integration_test.records_processed',
          1,
          tagkey: 'tagvalue',
          eventsource: response_payload['eventType']
        )
      end
    end
    Datadog::Lambda.metric(
      'serverless.integration_test.execution',
      1,
      tagkey: 'tagvalue',
      eventsource: response_payload['eventType']
    )

    puts "Processed #{response_payload['eventType']} request"
    response_payload
  end
end
