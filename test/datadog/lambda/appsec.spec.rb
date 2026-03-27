# frozen_string_literal: true

require 'datadog/lambda'
require 'datadog/lambda/appsec'

RSpec.describe Datadog::Lambda::AppSec do
  before do
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
    allow(gateway).to receive(:push)
  end

  let(:gateway) { instance_double(Datadog::AppSec::Instrumentation::Gateway) }
  let(:appsec_context) do
    instance_double(
      Datadog::AppSec::Context,
      state: {},
      export_metrics: nil,
      export_request_telemetry: nil,
    )
  end

  describe '.on_start' do
    subject(:on_start) { described_class.on_start(event, trace: trace, span: span) }

    let(:event) { {'httpMethod' => 'GET', 'path' => '/'} }
    let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
    let(:span) { instance_double(Datadog::Tracing::SpanOperation, set_metric: nil) }

    context 'when appsec is disabled' do
      before { allow(Datadog::AppSec).to receive(:enabled?).and_return(false) }

      it 'does not push to gateway' do
        on_start
        expect(gateway).not_to have_received(:push)
      end
    end

    context 'when appsec is enabled' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
        allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
        allow(Datadog::AppSec::Context).to receive(:new).and_return(appsec_context)
        allow(Datadog::AppSec::Context).to receive(:activate)
        allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context)
      end

      let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine::Engine, new_runner: waf_runner) }
      let(:waf_runner) { instance_double(Datadog::AppSec::SecurityEngine::Runner) }

      it 'creates and activates context with provided trace and span' do
        on_start

        aggregate_failures('context lifecycle') do
          expect(Datadog::AppSec::Context).to have_received(:new).with(trace, span, waf_runner)
          expect(Datadog::AppSec::Context).to have_received(:activate).with(appsec_context)
          expect(span).to have_received(:set_metric).with(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
        end
      end

      it 'pushes event to gateway' do
        on_start
        expect(gateway).to have_received(:push).with('aws_lambda.request.start', event)
      end

      context 'when security_engine is nil' do
        before do
          allow(Datadog::AppSec).to receive(:security_engine).and_return(nil)
          allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
        end

        it 'skips context activation and gateway push' do
          on_start

          aggregate_failures('skipped activation') do
            expect(Datadog::AppSec::Context).not_to have_received(:activate)
            expect(gateway).not_to have_received(:push)
          end
        end
      end

      context 'when trace is nil' do
        subject(:on_start) { described_class.on_start(event, trace: nil, span: span) }

        before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

        it 'skips context activation and gateway push' do
          on_start

          aggregate_failures('skipped activation') do
            expect(Datadog::AppSec::Context).not_to have_received(:activate)
            expect(gateway).not_to have_received(:push)
          end
        end
      end

      context 'when span is nil' do
        subject(:on_start) { described_class.on_start(event, trace: trace, span: nil) }

        before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

        it 'skips context activation and gateway push' do
          on_start

          aggregate_failures('skipped activation') do
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

    context 'when appsec is disabled' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(false)
        allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context)
      end

      it 'does not push to gateway' do
        on_finish
        expect(gateway).not_to have_received(:push)
      end
    end

    context 'when no active context exists' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
        allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
      end

      it 'does not push to gateway' do
        on_finish
        expect(gateway).not_to have_received(:push)
      end
    end

    context 'when active context exists' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
        allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context)
        allow(Datadog::AppSec::Context).to receive(:deactivate)
        allow(Datadog::AppSec::Event).to receive(:record)
      end

      it 'pushes response and records events' do
        on_finish

        aggregate_failures('response processing') do
          expect(gateway).to have_received(:push).with('aws_lambda.response.start', response)
          expect(Datadog::AppSec::Event).to have_received(:record).with(appsec_context, request: nil)
        end
      end

      it 'exports telemetry and deactivates' do
        on_finish

        aggregate_failures('cleanup') do
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
          expect(Datadog::AppSec::Event).to have_received(:record).with(appsec_context, request: request_data)
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
