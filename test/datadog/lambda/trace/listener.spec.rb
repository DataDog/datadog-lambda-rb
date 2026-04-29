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
end
