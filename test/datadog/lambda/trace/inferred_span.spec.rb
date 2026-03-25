# frozen_string_literal: true

require 'datadog/lambda'
require 'datadog/lambda/trace/inferred_span'
require_relative '../../lambdacontextversion'

describe Datadog::Lambda::Trace::InferredSpan do
  let(:request_context) { LambdaContextVersion.new }
  let(:trace_digest) { nil }

  let(:apigw_v1_event) do
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

  let(:apigw_v2_event) do
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

  before do
    allow(Datadog::Lambda).to receive(:trace_managed_services?).and_return(true)
  end

  describe '.create' do
    context 'when managed services is disabled' do
      before { allow(Datadog::Lambda).to receive(:trace_managed_services?).and_return(false) }

      it { expect(described_class.create(apigw_v1_event, request_context, trace_digest)).to be_nil }
    end

    context 'when event is not a Hash' do
      it { expect(described_class.create('not a hash', request_context, trace_digest)).to be_nil }
    end

    context 'when event has no requestContext' do
      it { expect(described_class.create({}, request_context, trace_digest)).to be_nil }
    end

    context 'when event has requestContext without stage' do
      let(:event) { {'requestContext' => {'apiId' => 'abc'}} }

      it { expect(described_class.create(event, request_context, trace_digest)).to be_nil }
    end

    context 'when event has no httpMethod or routeKey' do
      let(:event) { {'requestContext' => {'stage' => 'prod'}} }

      it { expect(described_class.create(event, request_context, trace_digest)).to be_nil }
    end

    context 'with API Gateway v1 event' do
      after { @span&.finish unless @span&.finished? }

      it 'creates an aws.apigateway span' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span).not_to be_nil
        expect(@span.name).to eq('aws.apigateway')
      end

      it 'sets service to domain name' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span.service).to eq('api.example.com')
      end

      it 'sets resource to method + resource path' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span.resource).to eq('GET /test')
      end

      it 'sets the inferred span metric' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span.get_metric('_dd._inferred_span')).to eq(1.0)
      end

      it 'sets http tags' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span.get_tag('http.method')).to eq('GET')
        expect(@span.get_tag('http.url')).to eq('https://api.example.com/test')
        expect(@span.get_tag('http.route')).to eq('/test')
      end

      it 'sets api gateway tags' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span.get_tag('apiid')).to eq('abc123')
        expect(@span.get_tag('stage')).to eq('prod')
      end

      it 'sets dd_resource_key with restapis prefix' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span.get_tag('dd_resource_key')).to eq(
          'arn:aws:apigateway:us-east-1::/restapis/abc123/stages/prod'
        )
      end

      it 'sets user agent tag' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span.get_tag('http.useragent')).to eq('TestAgent/1.0')
      end

      it 'sets start_time from requestTimeEpoch' do
        @span = described_class.create(apigw_v1_event, request_context, trace_digest)
        expect(@span.start_time).to eq(Time.at(1_700_000_000))
      end

      context 'when trace_digest is provided' do
        let(:trace_digest) { double('trace_digest') }
        let(:captured_kwargs) { {} }

        before do
          allow(Datadog::Tracing).to receive(:trace).and_wrap_original do |original, *args, **kwargs|
            captured_kwargs.merge!(kwargs)
            original.call(*args, **kwargs.except(:continue_from))
          end
        end

        it 'passes continue_from to trace' do
          @span = described_class.create(apigw_v1_event, request_context, trace_digest)
          expect(captured_kwargs[:continue_from]).to eq(trace_digest)
        end
      end

      context 'when domain is empty' do
        before { apigw_v1_event['requestContext']['domainName'] = '' }

        it 'uses path as http.url' do
          @span = described_class.create(apigw_v1_event, request_context, trace_digest)
          expect(@span.get_tag('http.url')).to eq('/test')
        end

        it 'sets service to nil' do
          @span = described_class.create(apigw_v1_event, request_context, trace_digest)
          expect(@span.service).not_to eq('')
        end
      end
    end

    context 'with API Gateway v2 event' do
      after { @span&.finish unless @span&.finished? }

      it 'creates an aws.httpapi span' do
        @span = described_class.create(apigw_v2_event, request_context, trace_digest)
        expect(@span).not_to be_nil
        expect(@span.name).to eq('aws.httpapi')
      end

      it 'extracts method from http context' do
        @span = described_class.create(apigw_v2_event, request_context, trace_digest)
        expect(@span.get_tag('http.method')).to eq('GET')
      end

      it 'extracts resource path from routeKey' do
        @span = described_class.create(apigw_v2_event, request_context, trace_digest)
        expect(@span.get_tag('http.route')).to eq('/test')
        expect(@span.resource).to eq('GET /test')
      end

      it 'sets dd_resource_key with apis prefix' do
        @span = described_class.create(apigw_v2_event, request_context, trace_digest)
        expect(@span.get_tag('dd_resource_key')).to eq(
          'arn:aws:apigateway:us-east-1::/apis/xyz789/stages/prod'
        )
      end

      it 'sets user agent from http context' do
        @span = described_class.create(apigw_v2_event, request_context, trace_digest)
        expect(@span.get_tag('http.useragent')).to eq('TestAgent/2.0')
      end
    end

    context 'when an error occurs' do
      before do
        allow(Datadog::Tracing).to receive(:trace).and_raise(StandardError, 'boom')
      end

      it 'returns nil' do
        expect(described_class.create(apigw_v1_event, request_context, trace_digest)).to be_nil
      end
    end
  end

  describe '.finish' do
    let(:inferred_span) { Datadog::Tracing.trace('test.inferred') }

    after { inferred_span&.finish unless inferred_span&.finished? }

    context 'when inferred_span is nil' do
      it { expect(described_class.finish(nil, {})).to be_nil }
    end

    context 'with a response containing statusCode' do
      it 'sets http.status_code tag and finishes the span' do
        described_class.finish(inferred_span, {'statusCode' => 200})
        expect(inferred_span.get_tag('http.status_code')).to eq('200')
        expect(inferred_span).to be_finished
      end
    end

    context 'when response is not a Hash' do
      it 'finishes the span without status tag' do
        described_class.finish(inferred_span, 'not a hash')
        expect(inferred_span.get_tag('http.status_code')).to be_nil
        expect(inferred_span).to be_finished
      end
    end

    context 'when response is nil' do
      it 'finishes the span without status tag' do
        described_class.finish(inferred_span, nil)
        expect(inferred_span.get_tag('http.status_code')).to be_nil
        expect(inferred_span).to be_finished
      end
    end

    context 'when an error occurs' do
      let(:inferred_span) { double('span', finished?: true) }

      before do
        allow(inferred_span).to receive(:set_tag)
        allow(inferred_span).to receive(:finish).and_raise(StandardError, 'boom')
      end

      it 'does not raise' do
        expect { described_class.finish(inferred_span, {}) }.not_to raise_error
      end
    end
  end
end
