# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require 'datadog/lambda'
require 'net/http'

describe Datadog::Utils do
  let(:headers) do
    {
      'x-datadog-parent-id' => '797643193680388254',
      'x-datadog-sampling-priority' => '1',
      'x-datadog-trace-id' => '4110911582297405557'
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
        expect(Net::HTTP).to receive(:post).with(Datadog::Utils::START_INVOCATION_URI, 'null', Datadog::Utils.request_headers) { headers }

        # Call the start request with an empty event
        Datadog::Utils.send_start_invocation_request(event: nil)

        digest = Datadog::Tracing.active_trace.to_digest

        expect(digest.trace_id.to_s).to eq('4110911582297405557')
        expect(digest.span_id.to_s).to eq('797643193680388254')
        expect(digest.trace_sampling_priority.to_s).to eq('1')
      end

      it 'skips applying trace context when headers are not present' do
        # Stub POST request to return a trace context
        expect(Net::HTTP).to receive(:post).with(Datadog::Utils::START_INVOCATION_URI, 'null', Datadog::Utils.request_headers) { {} }

        # Call the start request with an empty event
        Datadog::Utils.send_start_invocation_request(event: nil)

        digest = Datadog::Tracing.active_trace.to_digest

        expect(digest.trace_id.to_s).not_to eq('4110911582297405557')
        expect(digest.span_id.to_s).not_to eq('797643193680388254')
      end
    end

    context 'when extension is not running' do
      it 'does nothing' do
        result = Datadog::Utils.send_start_invocation_request(event: nil)
        expect(result).to eq(nil)
      end
    end
  end

  describe '#update_trace_context_on_response' do
    before(:each) do
      # Start tracing for active span
      @trace = Datadog::Tracing.trace('aws.lambda')
    end

    after(:each) do
      @trace.finish
    end

    it 'applies trace context from response' do
      Datadog::Utils.update_trace_context_on_response(response: headers)

      digest = Datadog::Tracing.active_trace.to_digest

      expect(digest.trace_id.to_s).to eq('4110911582297405557')
      expect(digest.span_id.to_s).to eq('797643193680388254')
      expect(digest.trace_sampling_priority.to_s).to eq('1')
    end

    it 'skips applying trace context when headers are not present' do
      Datadog::Utils.update_trace_context_on_response(response: {})

      digest = Datadog::Tracing.active_trace.to_digest

      expect(digest.trace_id.to_s).not_to eq('4110911582297405557')
      expect(digest.span_id.to_s).not_to eq('797643193680388254')
    end
  end

  describe '#headers_to_trace_context' do
    it 'returns a hash with trace context keys when headers are present' do
      result = Datadog::Utils.headers_to_trace_context(headers)

      expect(result[:trace_id]).to eq('4110911582297405557')
      expect(result[:parent_id]).to eq('797643193680388254')
      expect(result[:sample_mode]).to eq('1')
    end

    it 'returns an empty hash when headers are not present' do
      result = Datadog::Utils.headers_to_trace_context({})

      expect(result).to eq({})
    end
  end

  describe '#send_end_invocation_request' do
    context 'when extension is running' do
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
        Datadog::Utils.send_end_invocation_request(response: nil)
      end
    end

    context 'when extension is not running' do
      it 'does nothing' do
        result = Datadog::Utils.send_end_invocation_request(response: nil)
        expect(result).to eq(nil)
      end
    end
  end

  describe '#trace_context_to_headers' do
    it 'converts to datadog headers when trace context has values' do
      result = Datadog::Utils.trace_context_to_headers(trace_context)

      expect(result[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym]).to eq('4110911582297405557')
      expect(result[Datadog::Trace::DD_PARENT_ID_HEADER.to_sym]).to eq('797643193680388254')
      expect(result[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER.to_sym]).to eq('1')
    end

    it 'returns nil if trace context is not present' do
      expect(Datadog::Utils.trace_context_to_headers(nil)).to eq(nil)
    end
  end

  describe '#active_trace_context_to_headers' do
    it 'returns active trace context as headers' do
      trace = Datadog::Tracing.trace('aws.lambda')

      result = Datadog::Utils.active_trace_context_to_headers
      expect(result[Datadog::Trace::DD_TRACE_ID_HEADER.to_sym]).not_to eq(nil)
      expect(result[Datadog::Trace::DD_PARENT_ID_HEADER.to_sym]).not_to eq(nil)
      expect(result[Datadog::Trace::DD_SAMPLING_PRIORITY_HEADER.to_sym]).not_to eq(nil)

      trace.finish
    end
  end
end

# rubocop:enable Metrics/BlockLength
