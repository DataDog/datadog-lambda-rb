# frozen_string_literal: true

require 'datadog/lambda/appsec/request'

RSpec.describe Datadog::Lambda::AppSec::Request do
  subject(:request) { described_class.from_normalized(event) }

  let(:event) do
    {
      'headers' => {'Host' => 'example.com', 'User-Agent' => 'TestBot/1.0', 'Accept' => 'text/html'},
      'source_ip' => '10.0.0.1',
    }
  end

  describe '#headers' do
    it 'lowercases header keys' do
      expect(request.headers).to eq(
        'host' => 'example.com',
        'user-agent' => 'TestBot/1.0',
        'accept' => 'text/html'
      )
    end

    context 'when event has no headers' do
      let(:event) { {'source_ip' => '10.0.0.1'} }

      it { expect(request.headers).to eq({}) }
    end
  end

  describe '#host' do
    it { expect(request.host).to eq('example.com') }
  end

  describe '#user_agent' do
    it { expect(request.user_agent).to eq('TestBot/1.0') }
  end

  describe '#remote_addr' do
    it { expect(request.remote_addr).to eq('10.0.0.1') }

    context 'when source_ip is absent' do
      let(:event) { {'headers' => {}} }

      it { expect(request.remote_addr).to be_nil }
    end
  end
end
