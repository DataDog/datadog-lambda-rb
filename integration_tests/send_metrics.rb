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
      response_payload = process_records(event['Records'], response_payload)
    end

    send_metric('execution', response_payload['eventType'])
    puts "Processed #{response_payload['eventType']} request"
    response_payload
  end
end

def process_records(records, response_payload)
  records.each do |record|
    if record['messageId']
      response_payload['eventType'] = 'SQS'
      response_payload['recordIds'].push(record['messageId'])
      send_metric('records_processed', response_payload['eventType'])
    elsif record['Sns']
      response_payload['eventType'] = 'SNS'
      response_payload['recordIds'].push(record['Sns']['MessageId'])
      send_metric('records_processed', response_payload['eventType'])
    end
  end
  response_payload
end

def send_metric(name, event_type)
  Datadog::Lambda.metric(
    "serverless.integration_test.#{name}",
    1,
    tagkey: 'tagvalue',
    eventsource: event_type
  )
end
