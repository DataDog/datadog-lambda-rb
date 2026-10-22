# frozen_string_literal: true

require 'datadog/lambda/appsec/response'

RSpec.describe Datadog::Lambda::AppSec::Response do
  subject(:response) { described_class.from_normalized(normalized) }

  let(:normalized) do
    {
      'status_code' => 200,
      'headers' => {'content-type' => 'application/json'},
      'body' => '{"ok":true}'
    }
  end

  describe '#status' do
    it { expect(response.status).to eq(200) }

    context 'when status_code is a string' do
      let(:normalized) { {'status_code' => '403'} }

      it { expect(response.status).to eq(403) }
    end

    context 'when status_code is absent' do
      let(:normalized) { {'headers' => {}} }

      it { expect(response.status).to eq(0) }
    end
  end

  describe '#headers' do
    it { expect(response.headers).to eq('content-type' => 'application/json') }

    context 'when headers are absent' do
      let(:normalized) { {'status_code' => 204} }

      it { expect(response.headers).to eq({}) }
    end
  end

  describe '#body' do
    it { expect(response.body).to eq('{"ok":true}') }

    context 'when body is absent' do
      let(:normalized) { {'status_code' => 204} }

      it { expect(response.body).to be_nil }
    end
  end
end
