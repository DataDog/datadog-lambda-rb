# frozen_string_literal: true

require 'datadog/lambda/inferred_span/api_gateway_v1'
require 'datadog/lambda/event_source/api_gateway_v1'

RSpec.describe Datadog::Lambda::InferredSpan::ApiGatewayV1 do
  subject(:inferred_span) { described_class.new(event_source) }

  let(:event_source) { Datadog::Lambda::EventSource::ApiGatewayV1.new(payload) }
  let(:payload) do
    {
      'httpMethod' => 'GET',
      'path' => '/users/42',
      'requestContext' => {
        'stage' => 'prod',
        'domainName' => 'api.example.com',
        'apiId' => 'abc123',
        'resourcePath' => '/users/{id}',
        'requestTimeEpoch' => 1_700_000_000_000,
        'identity' => {'userAgent' => 'TestAgent/1.0'},
      },
    }
  end

  context 'when all fields are present' do
    it { expect(inferred_span.span_name).to eq('aws.apigateway') }
    it { expect(inferred_span.method).to eq('GET') }
    it { expect(inferred_span.path).to eq('/users/42') }
    it { expect(inferred_span.resource_path).to eq('/users/{id}') }
    it { expect(inferred_span.domain).to eq('api.example.com') }
    it { expect(inferred_span.api_id).to eq('abc123') }
    it { expect(inferred_span.stage).to eq('prod') }
    it { expect(inferred_span.request_time_ms).to eq(1_700_000_000_000) }
    it { expect(inferred_span.user_agent).to eq('TestAgent/1.0') }
    it { expect(inferred_span.arn_path_prefix).to eq('restapis') }
  end

  context 'when optional fields are missing' do
    let(:payload) { {'httpMethod' => 'POST', 'requestContext' => {'stage' => 'dev'}} }

    it { expect(inferred_span.path).to eq('/') }
    it { expect(inferred_span.resource_path).to eq('/') }
    it { expect(inferred_span.domain).to be_nil }
    it { expect(inferred_span.api_id).to be_nil }
    it { expect(inferred_span.stage).to eq('dev') }
    it { expect(inferred_span.request_time_ms).to be_nil }
    it { expect(inferred_span.user_agent).to be_nil }
  end
end
