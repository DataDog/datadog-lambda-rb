# frozen_string_literal: true

require 'datadog/lambda/event_source/api_gateway_v1'

RSpec.describe Datadog::Lambda::EventSource::ApiGatewayV1 do
  subject(:source) { described_class.new(payload) }

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
    it { expect(described_class.match?('requestContext' => {'stage' => 'prod'})).to be(false) }
    it { expect(described_class.match?('httpMethod' => 'GET')).to be(false) }

    it 'matches a v1 proxy integration event' do
      expect(
        described_class.match?('httpMethod' => 'GET', 'requestContext' => {'stage' => 'prod'})
      ).to be(true)
    end
  end

  context 'when all fields are present' do
    it { expect(source.method).to eq('GET') }
    it { expect(source.path).to eq('/users/42') }
    it { expect(source.resource_path).to eq('/users/{id}') }
    it { expect(source.domain).to eq('api.example.com') }
    it { expect(source.api_id).to eq('abc123') }
    it { expect(source.stage).to eq('prod') }
    it { expect(source.request_time_ms).to eq(1_700_000_000_000) }
    it { expect(source.user_agent).to eq('TestAgent/1.0') }
  end

  context 'when optional fields are missing' do
    let(:payload) { {'httpMethod' => 'POST', 'requestContext' => {'stage' => 'dev'}} }

    it { expect(source.path).to eq('/') }
    it { expect(source.resource_path).to eq('/') }
    it { expect(source.domain).to be_nil }
    it { expect(source.api_id).to be_nil }
    it { expect(source.stage).to eq('dev') }
    it { expect(source.request_time_ms).to be_nil }
    it { expect(source.user_agent).to be_nil }
  end
end
