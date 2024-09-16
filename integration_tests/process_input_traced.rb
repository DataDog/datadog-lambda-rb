# frozen_string_literal: true

require 'datadog/lambda'

Datadog::Lambda.configure_apm do |c|
end

def handle(event:, context:)
  Datadog::Lambda.wrap(event, context) do
    response_payload = {
      'message' => 'hello, dog!'
    }
    span = Datadog::Tracing.active_span
    Datadog::Lambda.metric('serverless.integration_test.execution', 1, function: 'http-request')
    record_ids, event_type = process_event(event:)
    response_payload['recordIds'] = record_ids if record_ids
    if event_type
      response_payload['eventType'] = event_type
    else
      request_id = get_api_gateway_request_id(event:)
      if request_id
        response_payload['eventType'] = 'APIGateway'
        span.set_tag('api_gateway_request_id', request_id)
      end
    end
    span.set_tag('event_type', response_payload['eventType'])
    response_payload
  end
end

def process_event(event:)
  Datadog::Tracing.trace('get_record_ids') do |_span|
    record_ids, event_type = get_record_ids(event:)
    if event_type
      span = Datadog::Tracing.active_span
      span.set_tag('record_event_type', event_type)
      span.set_tag('record_ids', record_ids.join)
    end
    return record_ids, event_type
  end
end

def get_record_ids(event:)
  record_ids = []
  event_type = nil
  if event.key?('Records')
    event['Records'].each do |record|
      if record['messageId']
        event_type = 'SQS'
        record_ids.push(record['messageId'])
      end

      if record.key?('Sns')
        event_type = 'SNS'
        record_ids.push(record['Sns']['MessageId'])
      end
    end
  end
  [record_ids, event_type]
end

def get_api_gateway_request_id(event:)
  Datadog::Tracing.trace('get_api_gateway_request_id') do |span|
    request_id = nil
    if event['requestContext']
      request_id = event['requestContext']['requestId']
      span = Datadog::Tracing.active_span
      span.set_tag('api_gateway_request_id', request_id)
      span.set_tag('event_type', 'APIGateway')
    end
    request_id
  end
end
