# frozen_string_literal: true

require 'datadog/lambda'
require 'net/http'
require_relative '../../lambdacontextversion'

describe Datadog::Utils do
  let(:headers) do
    {
      'x-datadog-parent-id' => '797643193680388254',
      'x-datadog-sampling-priority' => '1',
      'x-datadog-trace-id' => '4110911582297405557',
      'x-datadog-origin' => 'lambda',
    }
  end

  let(:ctx) { LambdaContextVersion.new }

  describe '#send_start_invocation_request' do
    context 'when extension is running' do
      before do
        allow(described_class).to receive(:extension_running?).and_return(true)
        @trace = Datadog::Tracing.trace('aws.lambda')
      end

      after { @trace.finish }

      it 'applies trace context from extension' do
        all_headers = described_class.request_headers
        all_headers['lambda-runtime-aws-request-id'] = ctx.aws_request_id
        expect(Net::HTTP).to receive(:post)
          .with(described_class::START_INVOCATION_URI, 'null', all_headers) { headers }

        digest = described_class.send_start_invocation_request(event: nil, request_context: ctx)

        expect(digest.trace_id.to_s).to eq('4110911582297405557')
        expect(digest.span_id.to_s).to eq('797643193680388254')
        expect(digest.trace_sampling_priority.to_s).to eq('1')
      end

      it 'skips applying trace context when headers are not present' do
        all_headers = described_class.request_headers
        all_headers['lambda-runtime-aws-request-id'] = ctx.aws_request_id
        expect(Net::HTTP).to receive(:post)
          .with(described_class::START_INVOCATION_URI, 'null', all_headers) { {} }

        described_class.send_start_invocation_request(event: nil, request_context: ctx)

        digest = Datadog::Tracing.active_trace.to_digest
        expect(digest.trace_id.to_s).not_to eq('4110911582297405557')
        expect(digest.span_id.to_s).not_to eq('797643193680388254')
      end
    end

    context 'when extension is not running' do
      it { expect(described_class.send_start_invocation_request(event: nil, request_context: ctx)).to be_nil }
    end
  end

  describe '#send_end_invocation_request' do
    context 'when extension is running' do
      before do
        allow(described_class).to receive(:extension_running?).and_return(true)
        @trace = Datadog::Tracing.trace('aws.lambda')
      end

      after { @trace.finish }

      it 'sends post request' do
        allow(Net::HTTP).to receive(:post) { nil }
        described_class.send_end_invocation_request(response: nil, span_id: nil, request_context: ctx)
      end

      context 'when active span has appsec tags' do
        before do
          @trace.set_metric('_dd.appsec.enabled', 1.0)
          @trace.set_tag('_dd.appsec.json', '{"triggers":[]}')
          allow(Net::HTTP).to receive(:start).and_yield(http_double)
          allow(http_double).to receive(:request) do |req|
            @captured_request = req
            Net::HTTPResponse.new('1.1', '200', 'OK')
          end
        end

        let(:http_double) { instance_double(Net::HTTP) }

        it 'does not forward appsec headers to the extension' do
          described_class.send_end_invocation_request(
            response: nil, span_id: nil, request_context: ctx
          )
          expect(@captured_request['x-datadog-appsec-enabled']).to be_nil
          expect(@captured_request['x-datadog-appsec-json']).to be_nil
        end
      end
    end

    context 'when extension is not running' do
      it { expect(described_class.send_end_invocation_request(response: nil, span_id: nil, request_context: ctx)).to be_nil }
    end
  end
end
