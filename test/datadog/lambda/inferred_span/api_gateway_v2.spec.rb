# frozen_string_literal: true

require 'datadog/lambda/inferred_span/api_gateway_v2'
require 'datadog/lambda/event_source/api_gateway_v2'

RSpec.describe Datadog::Lambda::InferredSpan::ApiGatewayV2 do
  subject(:inferred_span) { described_class.new(event_source) }

  let(:event_source) { Datadog::Lambda::EventSource::ApiGatewayV2.new(payload) }
  let(:payload) do
    {
      'rawPath' => '/users/42',
      'routeKey' => 'GET /users/{id}',
      'requestContext' => {
        'stage' => 'prod',
        'domainName' => 'api.example.com',
        'apiId' => 'xyz789',
        'timeEpoch' => 1_700_000_000_000,
        'http' => {'method' => 'GET', 'userAgent' => 'TestAgent/2.0'},
      },
    }
  end

  context 'when all fields are present' do
    it { expect(inferred_span.span_name).to eq('aws.httpapi') }
    it { expect(inferred_span.method).to eq('GET') }
    it { expect(inferred_span.path).to eq('/users/42') }
    it { expect(inferred_span.resource_path).to eq('/users/{id}') }
    it { expect(inferred_span.domain).to eq('api.example.com') }
    it { expect(inferred_span.api_id).to eq('xyz789') }
    it { expect(inferred_span.stage).to eq('prod') }
    it { expect(inferred_span.request_time_ms).to eq(1_700_000_000_000) }
    it { expect(inferred_span.user_agent).to eq('TestAgent/2.0') }
    it { expect(inferred_span.arn_path_prefix).to eq('apis') }
  end

  context 'when routeKey has no method prefix' do
    let(:payload) do
      {
        'rawPath' => '/test',
        'routeKey' => '$default',
        'requestContext' => {
          'stage' => 'prod',
          'http' => {'method' => 'GET'},
        },
      }
    end

    it { expect(inferred_span.resource_path).to eq('$default') }
  end

  context 'when optional fields are missing' do
    let(:payload) { {'routeKey' => 'POST /data', 'requestContext' => {'stage' => 'dev'}} }

    it { expect(inferred_span.path).to eq('/') }
    it { expect(inferred_span.resource_path).to eq('/data') }
    it { expect(inferred_span.domain).to be_nil }
    it { expect(inferred_span.api_id).to be_nil }
    it { expect(inferred_span.stage).to eq('dev') }
    it { expect(inferred_span.request_time_ms).to be_nil }
    it { expect(inferred_span.user_agent).to be_nil }
    it { expect(inferred_span.method).to be_nil }
  end
end
