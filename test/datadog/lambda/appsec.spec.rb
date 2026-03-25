# frozen_string_literal: true

require 'datadog/lambda'
require 'datadog/lambda/appsec'

describe Datadog::Lambda::AppSec do
  before do
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
    allow(gateway).to receive(:push)
    allow(Datadog::Tracing).to receive(:active_trace).and_return(active_trace)
  end

  let(:gateway) { double('gateway') }
  let(:active_trace) { double('active_trace') }
  let(:span) { double('span', set_metric: nil) }
  let(:runner) { double('runner') }
  let(:security_engine) { double('security_engine', new_runner: runner) }
  let(:appsec_context) do
    double(
      'context',
      state: {},
      export_metrics: nil,
      export_request_telemetry: nil,
    )
  end

  describe '.on_start' do
    subject(:on_start) { described_class.on_start(event, span) }

    let(:event) { {'httpMethod' => 'GET', 'path' => '/'} }

    context 'when appsec is disabled' do
      before { allow(Datadog::AppSec).to receive(:enabled?).and_return(false) }

      it 'does nothing' do
        aggregate_failures('no side effects') do
          expect(on_start).to be_nil
          expect(gateway).not_to have_received(:push)
        end
      end
    end

    context 'when appsec is enabled' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
        allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
        allow(Datadog::AppSec::Context).to receive(:activate)
        allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context)
        allow(Datadog::AppSec::Context).to receive(:new).and_return(appsec_context)
      end

      it 'activates context, marks span, and pushes event to gateway' do
        on_start

        aggregate_failures('context lifecycle') do
          expect(Datadog::AppSec::Context).to have_received(:new).with(active_trace, span, runner)
          expect(Datadog::AppSec::Context).to have_received(:activate).with(appsec_context)
        end

        aggregate_failures('span and gateway') do
          expect(span).to have_received(:set_metric).with(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
          expect(gateway).to have_received(:push).with('aws_lambda.request.start', event)
        end
      end

      context 'when span is not provided' do
        subject(:on_start) { described_class.on_start(event) }

        before { allow(Datadog::Tracing).to receive(:active_span).and_return(active_span) }

        let(:active_span) { double('active_span', set_metric: nil) }

        it 'falls back to active span' do
          on_start
          expect(Datadog::AppSec::Context).to have_received(:new).with(active_trace, active_span, runner)
        end
      end

      context 'when security_engine is nil' do
        before do
          allow(Datadog::AppSec).to receive(:security_engine).and_return(nil)
          allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
        end

        it 'does not activate or push' do
          on_start

          aggregate_failures('no side effects') do
            expect(Datadog::AppSec::Context).not_to have_received(:activate)
            expect(gateway).not_to have_received(:push)
          end
        end
      end

      context 'when trace is nil' do
        before do
          allow(Datadog::Tracing).to receive(:active_trace).and_return(nil)
          allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
        end

        it 'does not activate or push' do
          on_start

          aggregate_failures('no side effects') do
            expect(Datadog::AppSec::Context).not_to have_received(:activate)
            expect(gateway).not_to have_received(:push)
          end
        end
      end

      context 'when an error occurs' do
        before { allow(Datadog::AppSec::Context).to receive(:new).and_raise(StandardError, 'boom') }

        it { expect { on_start }.not_to raise_error }
      end
    end
  end

  describe '.on_finish' do
    subject(:on_finish) { described_class.on_finish(response) }

    let(:response) { {'statusCode' => 200} }

    context 'when no active context' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

      it 'does nothing' do
        aggregate_failures('no side effects') do
          expect(on_finish).to be_nil
          expect(gateway).not_to have_received(:push)
        end
      end
    end

    context 'when active context exists' do
      before do
        allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context)
        allow(Datadog::AppSec::Context).to receive(:deactivate)
        allow(Datadog::AppSec::Event).to receive(:record)
      end

      it 'processes response and cleans up' do
        on_finish

        aggregate_failures('gateway and event recording') do
          expect(gateway).to have_received(:push).with('aws_lambda.response.start', response)
          expect(Datadog::AppSec::Event).to have_received(:record).with(appsec_context, request: nil)
        end

        aggregate_failures('telemetry and cleanup') do
          expect(appsec_context).to have_received(:export_metrics)
          expect(appsec_context).to have_received(:export_request_telemetry)
          expect(Datadog::AppSec::Context).to have_received(:deactivate)
        end
      end

      context 'when context has a request in state' do
        before { appsec_context.state[:request] = request_data }

        let(:request_data) { double('request') }

        it 'passes request to event recording' do
          on_finish
          expect(Datadog::AppSec::Event).to have_received(:record).with(
            appsec_context, request: request_data
          )
        end
      end

      context 'when an error occurs' do
        before { allow(gateway).to receive(:push).and_raise(StandardError, 'boom') }

        it 'still deactivates the context' do
          on_finish
          expect(Datadog::AppSec::Context).to have_received(:deactivate)
        end
      end
    end
  end
end
