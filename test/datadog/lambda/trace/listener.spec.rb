# frozen_string_literal: true

require 'datadog/lambda/trace/listener'
require_relative '../../lambdacontext'

RSpec.describe Datadog::Trace::Listener do
  describe '#on_end' do
    before do
      allow(Datadog::Utils).to receive(:send_start_invocation_request).and_return(nil)
      allow(Datadog::Utils).to receive(:send_end_invocation_request)
      allow(Datadog::Tracing).to receive(:trace).and_return(span)
    end

    let(:listener) do
      described_class.new(
        handler_name: 'handler', function_name: 'my-function',
        patch_http: false, merge_xray_traces: false
      )
    end
    let(:request_context) { LambdaContext.new }
    let(:span) { instance_double(Datadog::Tracing::SpanOperation, id: 123, finish: nil) }

    context 'when inferred span exists' do
      before do
        allow(Datadog::Lambda::InferredSpan).to receive(:try_create).and_return(inferred_span)
        listener.on_start(event: {}, request_context: request_context, cold_start: false)
      end

      let(:inferred_span) { instance_double(Datadog::Tracing::SpanOperation, finish: nil) }

      it 'finishes lambda span before inferred span' do
        order = []
        allow(span).to receive(:finish) { order << :lambda }
        allow(inferred_span).to receive(:finish) { order << :inferred }

        listener.on_end(response: nil, request_context: request_context)
        expect(order).to eq(%i[lambda inferred])
      end
    end
  end
end
