# frozen_string_literal: true

require 'datadog/lambda/appsec/event_normalizer'

RSpec.describe Datadog::Lambda::AppSec::EventNormalizer do
  describe '.normalize' do
    subject(:result) { described_class.normalize(event) }

    context 'when event is API Gateway v1' do
      let(:event) do
        {
          'httpMethod' => 'POST',
          'path' => '/users/123',
          'headers' => {'Host' => 'example.com', 'Cookie' => 'session=abc'},
          'queryStringParameters' => {'page' => '1'},
          'multiValueQueryStringParameters' => {'page' => ['1']},
          'pathParameters' => {'id' => '123'},
          'body' => '{"name":"john"}',
          'isBase64Encoded' => false,
          'requestContext' => {'identity' => {'sourceIp' => '10.0.0.1'}},
        }
      end

      it { expect(result['method']).to eq('POST') }
      it { expect(result['path']).to eq('/users/123') }
      it { expect(result['headers']).to eq('Host' => 'example.com', 'Cookie' => 'session=abc') }
      it { expect(result['query']).to eq('page' => ['1']) }
      it { expect(result['source_ip']).to eq('10.0.0.1') }
      it { expect(result['body']).to eq('{"name":"john"}') }
      it { expect(result['base64_encoded']).to eq(false) }
      it { expect(result['path_params']).to eq('id' => '123') }
      it { expect(result).not_to have_key('cookies') }
      it { expect(result).not_to have_key('query_string') }
    end

    context 'when event is API Gateway v1 without multiValueQueryStringParameters' do
      let(:event) do
        {
          'httpMethod' => 'GET',
          'path' => '/health',
          'headers' => {},
          'queryStringParameters' => {'page' => '1'},
          'requestContext' => {'identity' => {}},
        }
      end

      it { expect(result['query']).to eq('page' => '1') }
    end

    context 'when event is API Gateway v2' do
      let(:event) do
        {
          'rawPath' => '/users/123',
          'rawQueryString' => 'page=1&sort=asc',
          'queryStringParameters' => {'page' => '1', 'sort' => 'asc'},
          'headers' => {'host' => 'example.com'},
          'cookies' => ['session=abc', 'theme=dark'],
          'pathParameters' => {'id' => '123'},
          'body' => 'hello',
          'isBase64Encoded' => false,
          'requestContext' => {'http' => {'method' => 'GET', 'sourceIp' => '10.0.0.2'}},
        }
      end

      it { expect(result['method']).to eq('GET') }
      it { expect(result['path']).to eq('/users/123') }
      it { expect(result['headers']).to eq('host' => 'example.com') }
      it { expect(result['cookies']).to eq(['session=abc', 'theme=dark']) }
      it { expect(result['query']).to eq('page' => '1', 'sort' => 'asc') }
      it { expect(result['query_string']).to eq('page=1&sort=asc') }
      it { expect(result['source_ip']).to eq('10.0.0.2') }
      it { expect(result['body']).to eq('hello') }
      it { expect(result['base64_encoded']).to eq(false) }
      it { expect(result['path_params']).to eq('id' => '123') }
    end

    context 'when v1 event has nil fields' do
      let(:event) do
        {
          'httpMethod' => 'GET',
          'path' => '/health',
          'headers' => nil,
          'queryStringParameters' => nil,
          'multiValueQueryStringParameters' => nil,
          'pathParameters' => nil,
          'body' => nil,
          'isBase64Encoded' => false,
          'requestContext' => {'identity' => {'sourceIp' => '127.0.0.1'}},
        }
      end

      it { expect(result['method']).to eq('GET') }
      it { expect(result['path']).to eq('/health') }
      it { expect(result['source_ip']).to eq('127.0.0.1') }
      it { expect(result).not_to have_key('headers') }
      it { expect(result).not_to have_key('query') }
      it { expect(result).not_to have_key('path_params') }
      it { expect(result).not_to have_key('body') }
    end

    context 'when v2 event has minimal fields' do
      let(:event) do
        {
          'rawPath' => '/health',
          'headers' => {},
          'requestContext' => {'http' => {'method' => 'GET', 'sourceIp' => '127.0.0.1'}},
        }
      end

      it { expect(result['method']).to eq('GET') }
      it { expect(result['path']).to eq('/health') }
      it { expect(result['source_ip']).to eq('127.0.0.1') }
      it { expect(result).not_to have_key('cookies') }
      it { expect(result).not_to have_key('query') }
      it { expect(result).not_to have_key('query_string') }
      it { expect(result).not_to have_key('body') }
      it { expect(result).not_to have_key('path_params') }
    end
  end
end
