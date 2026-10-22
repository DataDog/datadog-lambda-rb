# frozen_string_literal: true

require 'datadog/lambda/appsec/response_normalizer'

RSpec.describe Datadog::Lambda::AppSec::ResponseNormalizer do
  describe '.normalize' do
    subject(:result) { described_class.normalize(response) }

    context 'when response has all fields' do
      let(:response) do
        {
          'statusCode' => 200,
          'headers' => {'content-type' => 'application/json'},
          'body' => '{"ok":true}',
          'isBase64Encoded' => false
        }
      end

      it { expect(result['status_code']).to eq(200) }
      it { expect(result['headers']).to eq('content-type' => 'application/json') }
      it { expect(result['body']).to eq('{"ok":true}') }
      it { expect(result['base64_encoded']).to eq(false) }
    end

    context 'when response has multiValueHeaders only' do
      let(:response) do
        {
          'statusCode' => 200,
          'multiValueHeaders' => {'set-cookie' => ['a=1', 'b=2']}
        }
      end

      it { expect(result['headers']).to eq('set-cookie' => ['a=1', 'b=2']) }
    end

    context 'when response has both headers and multiValueHeaders' do
      let(:response) do
        {
          'statusCode' => 200,
          'headers' => {'content-type' => 'text/html', 'set-cookie' => 'a=1'},
          'multiValueHeaders' => {'set-cookie' => ['a=1', 'b=2']}
        }
      end

      it 'merges headers with multi-value taking priority' do
        expect(result['headers']).to eq(
          'content-type' => 'text/html',
          'set-cookie' => ['a=1', 'b=2']
        )
      end
    end

    context 'when response has nil fields' do
      let(:response) do
        {
          'statusCode' => 502,
          'headers' => nil,
          'body' => nil,
          'isBase64Encoded' => nil
        }
      end

      it { expect(result['status_code']).to eq(502) }
      it { expect(result).not_to have_key('headers') }
      it { expect(result).not_to have_key('body') }
      it { expect(result).not_to have_key('base64_encoded') }
    end

    context 'when response has only statusCode' do
      let(:response) { {'statusCode' => 204} }

      it { expect(result).to eq('status_code' => 204) }
    end

  end
end
