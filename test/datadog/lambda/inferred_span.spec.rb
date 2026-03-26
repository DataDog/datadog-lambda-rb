# frozen_string_literal: true

require 'datadog/lambda'
require 'datadog/lambda/inferred_span'
require_relative '../lambdacontextversion'

describe Datadog::Lambda::InferredSpan do
  let(:request_context) { LambdaContextVersion.new }
  let(:trace_digest) { nil }

  describe '.create' do
    subject(:created_span) { described_class.create(event, request_context, trace_digest) }

    after { created_span&.finish unless created_span&.finished? }

    context 'when event is not a Hash' do
      let(:event) { 'not a hash' }

      it { expect(created_span).to be_nil }
    end

    context 'when event has no requestContext' do
      let(:event) { {} }

      it { expect(created_span).to be_nil }
    end

    context 'when event has requestContext without stage' do
      let(:event) { {'requestContext' => {'apiId' => 'abc'}} }

      it { expect(created_span).to be_nil }
    end

    context 'when event has no httpMethod or routeKey' do
      let(:event) { {'requestContext' => {'stage' => 'prod'}} }

      it { expect(created_span).to be_nil }
    end

    context 'with API Gateway v1 event' do
      let(:event) do
        {
          'httpMethod' => 'GET',
          'path' => '/test',
          'requestContext' => {
            'stage' => 'prod',
            'domainName' => 'api.example.com',
            'apiId' => 'abc123',
            'resourcePath' => '/test',
            'requestTimeEpoch' => 1_700_000_000_000,
            'identity' => {'userAgent' => 'TestAgent/1.0', 'sourceIp' => '1.2.3.4'},
          },
        }
      end

      it 'creates a span representing the API Gateway' do
        aggregate_failures('span identity') do
          expect(created_span.name).to eq('aws.apigateway')
          expect(created_span.service).to eq('api.example.com')
          expect(created_span.resource).to eq('GET /test')
          expect(created_span.type).to eq('web')
          expect(created_span.start_time).to eq(Time.at(1_700_000_000))
        end
      end

      it 'sets tags for endpoint discovery' do
        aggregate_failures('http tags') do
          expect(created_span.get_tag('http.method')).to eq('GET')
          expect(created_span.get_tag('http.url')).to eq('https://api.example.com/test')
          expect(created_span.get_tag('http.route')).to eq('/test')
          expect(created_span.get_tag('http.useragent')).to eq('TestAgent/1.0')
          expect(created_span.get_tag('span.kind')).to eq('server')
        end
      end

      it 'sets tags for API Gateway resource correlation' do
        aggregate_failures('gateway tags') do
          expect(created_span.get_tag('apiid')).to eq('abc123')
          expect(created_span.get_tag('stage')).to eq('prod')
          expect(created_span.get_tag('request_id')).to eq(request_context.aws_request_id)
          expect(created_span.get_tag('dd_resource_key')).to eq(
            'arn:aws:apigateway:us-east-1::/restapis/abc123/stages/prod'
          )
        end
      end

      it 'marks the span as inferred' do
        aggregate_failures('inferred span markers') do
          expect(created_span.get_metric('_dd._inferred_span')).to eq(1.0)
          expect(created_span.get_tag('_inferred_span.synchronicity')).to eq('sync')
          expect(created_span.get_tag('_inferred_span.tag_source')).to eq('self')
        end
      end

      context 'when trace_digest is provided' do
        before do
          allow(Datadog::Tracing).to receive(:trace).and_wrap_original do |original, *args, **kwargs|
            @captured_kwargs = kwargs
            original.call(*args, **kwargs.except(:continue_from))
          end
        end

        let(:trace_digest) { double('trace_digest') }

        it 'continues from the existing trace' do
          created_span
          expect(@captured_kwargs[:continue_from]).to eq(trace_digest)
        end
      end

      context 'when domain is empty' do
        let(:event) do
          {
            'httpMethod' => 'GET',
            'path' => '/test',
            'requestContext' => {
              'stage' => 'prod',
              'domainName' => '',
              'apiId' => 'abc123',
              'resourcePath' => '/test',
              'requestTimeEpoch' => 1_700_000_000_000,
            },
          }
        end

        it { expect(created_span.get_tag('http.url')).to eq('/test') }
        it { expect(created_span.service).not_to eq('') }
      end

      context 'when requestTimeEpoch is nil' do
        let(:event) do
          {
            'httpMethod' => 'GET',
            'path' => '/test',
            'requestContext' => {
              'stage' => 'prod',
              'domainName' => 'api.example.com',
              'apiId' => 'abc123',
              'resourcePath' => '/test',
            },
          }
        end

        it { expect(created_span).not_to be_nil }
      end

      context 'when apiId is empty' do
        let(:event) do
          {
            'httpMethod' => 'GET',
            'path' => '/test',
            'requestContext' => {
              'stage' => 'prod',
              'domainName' => 'api.example.com',
              'apiId' => '',
              'resourcePath' => '/test',
            },
          }
        end

        it { expect(created_span.get_tag('dd_resource_key')).to be_nil }
      end
    end

    context 'with API Gateway v2 event' do
      let(:event) do
        {
          'rawPath' => '/test',
          'routeKey' => 'GET /test',
          'requestContext' => {
            'stage' => 'prod',
            'domainName' => 'api.example.com',
            'apiId' => 'xyz789',
            'timeEpoch' => 1_700_000_000_000,
            'http' => {'method' => 'GET', 'userAgent' => 'TestAgent/2.0'},
          },
        }
      end

      it 'creates a span representing the HTTP API' do
        aggregate_failures('span identity') do
          expect(created_span.name).to eq('aws.httpapi')
          expect(created_span.service).to eq('api.example.com')
          expect(created_span.resource).to eq('GET /test')
          expect(created_span.type).to eq('web')
        end
      end

      it 'sets tags for endpoint discovery' do
        aggregate_failures('http tags') do
          expect(created_span.get_tag('http.method')).to eq('GET')
          expect(created_span.get_tag('http.url')).to eq('https://api.example.com/test')
          expect(created_span.get_tag('http.route')).to eq('/test')
          expect(created_span.get_tag('http.useragent')).to eq('TestAgent/2.0')
          expect(created_span.get_tag('span.kind')).to eq('server')
        end
      end

      it 'sets tags for API Gateway resource correlation' do
        aggregate_failures('gateway tags') do
          expect(created_span.get_tag('apiid')).to eq('xyz789')
          expect(created_span.get_tag('stage')).to eq('prod')
          expect(created_span.get_tag('dd_resource_key')).to eq(
            'arn:aws:apigateway:us-east-1::/apis/xyz789/stages/prod'
          )
        end
      end

      context 'when routeKey has no method prefix' do
        let(:event) do
          {
            'rawPath' => '/test',
            'routeKey' => '$default',
            'requestContext' => {
              'stage' => 'prod',
              'domainName' => 'api.example.com',
              'apiId' => 'xyz789',
              'timeEpoch' => 1_700_000_000_000,
              'http' => {'method' => 'GET'},
            },
          }
        end

        it 'uses routeKey as-is for route' do
          aggregate_failures('route and resource') do
            expect(created_span.get_tag('http.route')).to eq('$default')
            expect(created_span.resource).to eq('GET $default')
          end
        end
      end
    end

    context 'when an error occurs' do
      before { allow(Datadog::Tracing).to receive(:trace).and_raise(StandardError, 'boom') }

      let(:event) do
        {
          'httpMethod' => 'GET',
          'path' => '/test',
          'requestContext' => {'stage' => 'prod'},
        }
      end

      it { expect(created_span).to be_nil }
    end
  end

end
