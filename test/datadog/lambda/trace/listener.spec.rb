# frozen_string_literal: true

require 'datadog/lambda/trace/listener'
require_relative '../../lambdacontext'

RSpec.describe Datadog::Trace::Listener do
  describe '#on_start' do
    before do
      allow(Datadog::Utils).to receive(:send_start_invocation_request).and_return(nil)
      allow(Datadog::Tracing).to receive(:trace).and_return(
        instance_double(Datadog::Tracing::SpanOperation)
      )
    end

    let(:request_context) { LambdaContext.new }
    let(:on_start) do
      listener.on_start(event: {}, request_context: request_context, cold_start: false)
    end

    context 'when DD_SERVICE is configured' do
      before { allow(Datadog.configuration).to receive(:service).and_return('my-custom-service') }

      let(:listener) do
        described_class.new(
          handler_name: 'handler', function_name: 'my-function',
          patch_http: false, merge_xray_traces: false
        )
      end

      it 'uses DD_SERVICE for service and function name for resource' do
        on_start
        expect(Datadog::Tracing).to have_received(:trace).with(
          'aws.lambda',
          hash_including(service: 'my-custom-service', resource: 'my-function')
        )
      end
    end

    context 'when DD_SERVICE is not configured' do
      before { allow(Datadog.configuration).to receive(:service).and_return(nil) }

      let(:listener) do
        described_class.new(
          handler_name: 'handler', function_name: 'my-function',
          patch_http: false, merge_xray_traces: false
        )
      end

      it 'uses function name for both service and resource' do
        on_start
        expect(Datadog::Tracing).to have_received(:trace).with(
          'aws.lambda',
          hash_including(service: 'my-function', resource: 'my-function')
        )
      end
    end

    context 'when function_name is nil' do
      before { allow(Datadog.configuration).to receive(:service).and_return(nil) }

      let(:listener) do
        described_class.new(
          handler_name: 'handler', function_name: nil,
          patch_http: false, merge_xray_traces: false
        )
      end

      it 'falls back to aws.lambda for both service and resource' do
        on_start
        expect(Datadog::Tracing).to have_received(:trace).with(
          'aws.lambda',
          hash_including(service: 'aws.lambda', resource: 'aws.lambda')
        )
      end
    end
  end

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
