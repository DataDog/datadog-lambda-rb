# frozen_string_literal: true

require 'datadog/lambda/inferred_span/api_gateway_v1'

RSpec.describe Datadog::Lambda::InferredSpan::ApiGatewayV1 do
  subject(:parser) { described_class.new(payload) }

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

  describe '.match?' do
    it { expect(described_class.match?('not a hash')).to be(false) }
    it { expect(described_class.match?({})).to be(false) }
    it { expect(described_class.match?({'requestContext' => {'stage' => 'prod'}})).to be(false) }
    it { expect(described_class.match?({'httpMethod' => 'GET'})).to be(false) }

    it 'matches a v1 proxy integration event' do
      expect(
        described_class.match?('httpMethod' => 'GET', 'requestContext' => {'stage' => 'prod'})
      ).to be(true)
    end
  end

  context 'when all fields are present' do
    it { expect(parser.span_name).to eq('aws.apigateway') }
    it { expect(parser.method).to eq('GET') }
    it { expect(parser.path).to eq('/users/42') }
    it { expect(parser.resource_path).to eq('/users/{id}') }
    it { expect(parser.domain).to eq('api.example.com') }
    it { expect(parser.api_id).to eq('abc123') }
    it { expect(parser.stage).to eq('prod') }
    it { expect(parser.request_time_ms).to eq(1_700_000_000_000) }
    it { expect(parser.user_agent).to eq('TestAgent/1.0') }
    it { expect(parser.arn_path_prefix).to eq('restapis') }
  end

  context 'when optional fields are missing' do
    let(:payload) { {'httpMethod' => 'POST', 'requestContext' => {'stage' => 'dev'}} }

    it { expect(parser.path).to eq('/') }
    it { expect(parser.resource_path).to eq('/') }
    it { expect(parser.domain).to eq('') }
    it { expect(parser.api_id).to eq('') }
    it { expect(parser.stage).to eq('dev') }
    it { expect(parser.request_time_ms).to be_nil }
    it { expect(parser.user_agent).to be_nil }
  end
end
