# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require 'datadog/lambda'
require 'net/http'
require_relative '../../lambdacontextversion'

describe Datadog::Utils do
  let(:headers) do
    {
      'x-datadog-parent-id' => '797643193680388254',
      'x-datadog-sampling-priority' => '1',
      'x-datadog-trace-id' => '4110911582297405557',
      'x-datadog-origin' => 'lambda'
    }
  end

  let(:trace_context) do
    {
      trace_id: '4110911582297405557',
      sample_mode: '1',
      parent_id: '797643193680388254'
    }
  end

  describe '#send_start_invocation_request' do
    context 'when extension is running' do
      ctx = LambdaContextVersion.new
      before(:each) do
        # Stub the extension_running? method to return true
        allow(Datadog::Utils).to receive(:extension_running?).and_return(true)

        # Start tracing for active span
        @trace = Datadog::Tracing.trace('aws.lambda')
      end

      after(:each) do
        @trace.finish
      end

      it 'applies trace context from extension' do
        # Stub POST request to return a trace context
        expect(Net::HTTP).to receive(:post)
          .with(Datadog::Utils::START_INVOCATION_URI, 'null', Datadog::Utils.request_headers) { headers }

        # Call the start request with an empty event
        digest = Datadog::Utils.send_start_invocation_request(event: nil, request_context: ctx)

        expect(digest.trace_id.to_s).to eq('4110911582297405557')
        expect(digest.span_id.to_s).to eq('797643193680388254')
        expect(digest.trace_sampling_priority.to_s).to eq('1')
      end

      it 'skips applying trace context when headers are not present' do
        # Stub POST request to return a trace context
        expect(Net::HTTP).to receive(:post)
          .with(Datadog::Utils::START_INVOCATION_URI, 'null', Datadog::Utils.request_headers) { {} }

        # Call the start request with an empty event
        Datadog::Utils.send_start_invocation_request(event: nil, request_context: ctx)

        digest = Datadog::Tracing.active_trace.to_digest

        expect(digest.trace_id.to_s).not_to eq('4110911582297405557')
        expect(digest.span_id.to_s).not_to eq('797643193680388254')
      end
    end

    context 'when extension is not running' do
      ctx = LambdaContextVersion.new
      it 'does nothing' do
        result = Datadog::Utils.send_start_invocation_request(event: nil, request_context: ctx)
        expect(result).to eq(nil)
      end
    end
  end

  describe '#send_end_invocation_request' do
    context 'when extension is running' do
      ctx = LambdaContextVersion.new
      before(:each) do
        # Stub the extension_running? method to return true
        allow(Datadog::Utils).to receive(:extension_running?).and_return(true)

        # Start tracing for active span
        @trace = Datadog::Tracing.trace('aws.lambda')
      end

      after(:each) do
        @trace.finish
      end

      it 'sends post request as expected' do
        # Stub POST request to not do anything
        allow(Net::HTTP).to receive(:post) { nil }

        # Call the start request with an empty event
        Datadog::Utils.send_end_invocation_request(response: nil, span_id: nil, request_context: ctx)
      end
    end

    context 'when extension is not running' do
      ctx = LambdaContextVersion.new
      it 'does nothing' do
        result = Datadog::Utils.send_end_invocation_request(response: nil, span_id: nil, request_context: ctx)
        expect(result).to eq(nil)
      end
    end
  end
end

# rubocop:enable Metrics/BlockLength
