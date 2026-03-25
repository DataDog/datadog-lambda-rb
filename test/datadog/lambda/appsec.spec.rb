# frozen_string_literal: true

require 'datadog/lambda'
require 'datadog/lambda/appsec'

describe Datadog::Lambda::AppSec do
  let(:event) { {'httpMethod' => 'GET', 'path' => '/'} }
  let(:active_trace) { double('active_trace') }
  let(:span) { double('span', set_metric: nil) }
  let(:gateway) { double('gateway') }
  let(:runner) { double('runner') }
  let(:security_engine) { double('security_engine', new_runner: runner) }
  let(:context) do
    double(
      'context',
      state: {},
      export_metrics: nil,
      export_request_telemetry: nil,
      events: [],
    )
  end

  before do
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
    allow(gateway).to receive(:push)
    allow(Datadog::Tracing).to receive(:active_trace).and_return(active_trace)
  end

  describe '.on_start' do
    context 'when appsec is disabled' do
      before { allow(Datadog::AppSec).to receive(:enabled?).and_return(false) }

      it { expect(described_class.on_start(event, span)).to be_nil }

      it 'does not push gateway events' do
        described_class.on_start(event, span)
        expect(gateway).not_to have_received(:push)
      end
    end

    context 'when appsec is enabled' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
        allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
        allow(Datadog::AppSec::Context).to receive(:activate)
        allow(Datadog::AppSec::Context).to receive(:active).and_return(context)
        allow(Datadog::AppSec::Context).to receive(:new).and_return(context)
      end

      it 'creates context with active_trace and the given span' do
        described_class.on_start(event, span)
        expect(Datadog::AppSec::Context).to have_received(:new).with(active_trace, span, runner)
        expect(Datadog::AppSec::Context).to have_received(:activate).with(context)
      end

      it 'sets _dd.appsec.enabled metric on span' do
        described_class.on_start(event, span)
        expect(span).to have_received(:set_metric).with(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
      end

      it 'pushes the request event to the gateway' do
        described_class.on_start(event, span)
        expect(gateway).to have_received(:push).with('aws_lambda.request.start', event)
      end

      context 'when span is not provided' do
        let(:active_span) { double('active_span', set_metric: nil) }

        before { allow(Datadog::Tracing).to receive(:active_span).and_return(active_span) }

        it 'falls back to active span' do
          described_class.on_start(event)
          expect(Datadog::AppSec::Context).to have_received(:new).with(active_trace, active_span, runner)
        end
      end

      context 'when security_engine is nil' do
        before do
          allow(Datadog::AppSec).to receive(:security_engine).and_return(nil)
          allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
        end

        it 'does not activate a context' do
          described_class.on_start(event, span)
          expect(Datadog::AppSec::Context).not_to have_received(:activate)
        end

        it 'does not push gateway events' do
          described_class.on_start(event, span)
          expect(gateway).not_to have_received(:push)
        end
      end

      context 'when an error occurs' do
        before { allow(Datadog::AppSec::Context).to receive(:new).and_raise(StandardError, 'boom') }

        it 'rescues and logs' do
          expect { described_class.on_start(event, span) }.not_to raise_error
        end
      end
    end
  end

  describe '.on_finish' do
    let(:response) { {'statusCode' => 200} }

    context 'when no active context' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

      it { expect(described_class.on_finish(response)).to be_nil }

      it 'does not push gateway events' do
        described_class.on_finish(response)
        expect(gateway).not_to have_received(:push)
      end
    end

    context 'when active context exists' do
      before do
        allow(Datadog::AppSec::Context).to receive(:active).and_return(context)
        allow(Datadog::AppSec::Context).to receive(:deactivate)
        allow(Datadog::AppSec::Event).to receive(:record)
      end

      it 'pushes the response event to the gateway' do
        described_class.on_finish(response)
        expect(gateway).to have_received(:push).with('aws_lambda.response.start', response)
      end

      it 'records events with the request from context state' do
        context.state[:request] = double('request')
        described_class.on_finish(response)
        expect(Datadog::AppSec::Event).to have_received(:record).with(
          context, request: context.state[:request]
        )
      end

      it 'exports metrics and telemetry' do
        described_class.on_finish(response)
        expect(context).to have_received(:export_metrics)
        expect(context).to have_received(:export_request_telemetry)
      end

      it 'deactivates the context' do
        described_class.on_finish(response)
        expect(Datadog::AppSec::Context).to have_received(:deactivate)
      end

      context 'when an error occurs' do
        before { allow(gateway).to receive(:push).and_raise(StandardError, 'boom') }

        it 'still deactivates the context' do
          described_class.on_finish(response)
          expect(Datadog::AppSec::Context).to have_received(:deactivate)
        end
      end
    end
  end
end
