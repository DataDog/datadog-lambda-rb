# frozen_string_literal: true

require 'datadog/lambda'
require 'datadog/lambda/appsec'

RSpec.describe Datadog::Lambda::AppSec do
  before do
    stub_const('Datadog::AppSec::WAF::VERSION::BASE_STRING', '1.30.0')

    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
    allow(gateway).to receive(:push)
  end

  let(:gateway) { instance_double(Datadog::AppSec::Instrumentation::Gateway) }
  let(:context_span) { instance_double(Datadog::Tracing::SpanOperation, set_tag: nil, set_metric: nil) }
  let(:appsec_context) do
    instance_double(
      Datadog::AppSec::Context,
      span: context_span, state: {}, export_metrics: nil, export_request_telemetry: nil
    )
  end

  describe '.on_start' do
    let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
    let(:span) { instance_double(Datadog::Tracing::SpanOperation, set_metric: nil, set_tag: nil) }

    context 'when appsec is disabled' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(false)
        described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)
      end

      it 'does not push to gateway' do
        expect(gateway).not_to have_received(:push)
      end
    end

    context 'when appsec is enabled' do
      before do
        allow(Datadog::AppSec).to receive_messages(enabled?: true, security_engine: security_engine)
        allow(Datadog::AppSec::Context).to receive_messages(activate: nil, active: appsec_context)
      end

      let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine::Engine, new_runner: waf_runner) }
      let(:waf_runner) { instance_double(Datadog::AppSec::SecurityEngine::Runner, ruleset_version: nil) }

      it 'marks span as appsec-enabled' do
        described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)

        expect(span).to have_received(:set_metric).with(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
      end

      it 'pushes event to gateway' do
        described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)

        expect(gateway).to have_received(:push).with(
          'aws_lambda.request.start', kind_of(Datadog::AppSec::Instrumentation::Gateway::DataContainer)
        )
      end

      context 'when security_engine is nil' do
        before do
          allow(Datadog::AppSec).to receive(:security_engine).and_return(nil)
          allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
          described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)
        end

        it 'skips context activation and gateway push' do
          aggregate_failures('skipped activation') do
            expect(Datadog::AppSec::Context).not_to have_received(:activate)
            expect(gateway).not_to have_received(:push)
          end
        end
      end

      context 'when trace is nil' do
        before do
          allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
          described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: nil, span: span)
        end

        it 'skips context activation and gateway push' do
          aggregate_failures('skipped activation') do
            expect(Datadog::AppSec::Context).not_to have_received(:activate)
            expect(gateway).not_to have_received(:push)
          end
        end
      end

      context 'when span is nil' do
        before do
          allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
          described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: nil)
        end

        it 'skips context activation and gateway push' do
          aggregate_failures('skipped activation') do
            expect(Datadog::AppSec::Context).not_to have_received(:activate)
            expect(gateway).not_to have_received(:push)
          end
        end
      end

      context 'when gateway push triggers a blocking interrupt' do
        before do
          allow(Datadog::AppSec::Context).to receive(:new).and_return(appsec_context)
          allow(appsec_context).to receive_messages(
            trace: trace,
            waf_runner_ruleset_version: nil,
            mark_as_interrupted!: nil
          )

          allow(gateway).to receive(:push).and_invoke(lambda { |_name, _payload|
            throw(Datadog::AppSec::Ext::INTERRUPT, {'status_code' => 403, 'type' => 'auto'})
          })
        end

        it 'returns a Lambda-shaped blocking response' do
          result = described_class.on_start(
            {'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span
          )

          expect(result).to include(
            'statusCode' => 403,
            'headers' => {'Content-Type' => 'application/json'},
            'body' => include('blocked')
          )
        end
      end

      context 'when an error occurs' do
        before do
          allow(Datadog::AppSec::Context).to receive(:new).and_raise(StandardError, 'boom')
          allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
        end

        it 'does not raise' do
          expect {
            described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)
          }.not_to raise_error
        end
      end

      context 'when waf ruleset is loaded' do
        before do
          allow(Datadog::AppSec::Context).to receive(:new).and_return(appsec_context)
          allow(appsec_context).to receive_messages(
            waf_runner_ruleset_version: '1.12.0',
            waf_runner_known_addresses: ['server.request.headers.no_cookies']
          )

          allow(trace).to receive_messages(keep!: nil, set_tag: nil)
          allow(span).to receive(:set_tag)
        end

        let(:appsec_context) do
          instance_double(
            Datadog::AppSec::Context,
            span: span, trace: trace, state: {}, export_metrics: nil, export_request_telemetry: nil
          )
        end

        it 'sets runtime family and WAF version on the span' do
          described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)

          aggregate_failures('appsec span tags') do
            expect(span).to have_received(:set_tag).with('_dd.runtime_family', 'ruby')
            expect(span).to have_received(:set_tag).with('_dd.appsec.waf.version', '1.30.0')
          end
        end

        it 'sets event rules version from the WAF runner' do
          described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)

          expect(span).to have_received(:set_tag).with('_dd.appsec.event_rules.version', '1.12.0')
        end

        context 'when cold_start is true' do
          before do
            described_class.on_start(
              {'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span, cold_start: true
            )
          end

          it 'sets known addresses and keeps trace' do
            aggregate_failures('cold start tags') do
              expect(span).to have_received(:set_tag).with(
                '_dd.appsec.event_rules.addresses',
                '["server.request.headers.no_cookies"]'
              )

              expect(trace).to have_received(:keep!)
              expect(trace).to have_received(:set_tag).with(
                Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
                Datadog::Tracing::Sampling::Ext::Decision::ASM
              )
            end
          end
        end

        context 'when cold_start is false' do
          before do
            described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)
          end

          it 'does not send cold start tags' do
            aggregate_failures('no cold start tags') do
              expect(span).not_to have_received(:set_tag).with('_dd.appsec.event_rules.addresses', anything)
              expect(trace).not_to have_received(:keep!)
            end
          end
        end

        context 'when ruleset version is not set' do
          before do
            allow(appsec_context).to receive(:waf_runner_ruleset_version).and_return(nil)
            described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)
          end

          it 'skips event rules tags' do
            aggregate_failures('skipped rules tags') do
              expect(span).not_to have_received(:set_tag).with('_dd.appsec.event_rules.version', anything)
              expect(span).not_to have_received(:set_tag).with('_dd.appsec.event_rules.addresses', anything)
            end
          end
        end

        context 'when span is not set' do
          before do
            allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
            described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: nil)
          end

          it 'does not set any appsec tags' do
            expect(span).not_to have_received(:set_tag)
          end
        end

        context 'when context trace is not set' do
          before do
            allow(appsec_context).to receive(:trace).and_return(nil)
            described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)
          end

          it 'does not set any tags' do
            aggregate_failures('no tags when trace nil') do
              expect(span).not_to have_received(:set_tag)
              expect(span).not_to have_received(:set_metric).with(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, anything)
            end
          end
        end
      end
    end
  end

  describe '.on_finish' do
    context 'when appsec is disabled' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(false)
        allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context)
        described_class.on_finish({'statusCode' => 200})
      end

      it 'does not push to gateway' do
        expect(gateway).not_to have_received(:push)
      end
    end

    context 'when no active context exists' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
        allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
        described_class.on_finish({'statusCode' => 200})
      end

      it 'does not push to gateway' do
        expect(gateway).not_to have_received(:push)
      end
    end

    context 'when active context exists' do
      before do
        allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
        allow(Datadog::AppSec::Context).to receive_messages(active: appsec_context, deactivate: nil)
        allow(Datadog::AppSec::Event).to receive(:record)
      end

      it 'pushes response and records events' do
        described_class.on_finish({'statusCode' => 200})

        aggregate_failures('response processing') do
          expect(gateway).to have_received(:push).with(
            'aws_lambda.response.start', kind_of(Datadog::AppSec::Instrumentation::Gateway::DataContainer)
          )
          expect(Datadog::AppSec::Event).to have_received(:record).with(appsec_context, request: anything)
        end
      end

      it 'exports telemetry and deactivates' do
        described_class.on_finish({'statusCode' => 200})

        aggregate_failures('AppSec deactivation') do
          expect(appsec_context).to have_received(:export_metrics)
          expect(appsec_context).to have_received(:export_request_telemetry)
          expect(Datadog::AppSec::Context).to have_received(:deactivate)
        end
      end

      context 'when a security event occurs' do
        before do
          allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
          allow(Datadog::AppSec::Context).to receive(:activate)

          described_class.on_start(
            {
              'httpMethod' => 'GET',
              'headers' => {'Host' => 'example.com', 'User-Agent' => 'TestBot'},
              'requestContext' => {'identity' => {'sourceIp' => '1.2.3.4'}}
            },
            trace: trace, span: span
          )
          described_class.on_finish({'statusCode' => 200})
        end

        let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
        let(:span) { instance_double(Datadog::Tracing::SpanOperation, set_metric: nil, set_tag: nil) }
        let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine::Engine, new_runner: waf_runner) }
        let(:waf_runner) { instance_double(Datadog::AppSec::SecurityEngine::Runner, ruleset_version: nil) }

        it 'records security event with request' do
          expect(Datadog::AppSec::Event).to have_received(:record).with(
            appsec_context, request: kind_of(Datadog::Lambda::AppSec::Request)
          )
        end
      end

      context 'when gateway push triggers a blocking interrupt' do
        before do
          allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
          allow(Datadog::AppSec::Context).to receive(:activate)
          allow(appsec_context).to receive(:mark_as_interrupted!)
          allow(gateway).to receive(:push).and_invoke(lambda { |_name, _payload|
            throw(Datadog::AppSec::Ext::INTERRUPT, {'status_code' => 403, 'type' => 'auto'})
          })

          described_class.on_start(
            {'httpMethod' => 'GET', 'headers' => {'Accept' => 'application/json'}},
            trace: trace, span: span
          )
        end

        let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
        let(:span) { instance_double(Datadog::Tracing::SpanOperation, set_metric: nil, set_tag: nil) }
        let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine::Engine, new_runner: waf_runner) }
        let(:waf_runner) { instance_double(Datadog::AppSec::SecurityEngine::Runner, ruleset_version: nil) }

        it 'returns a Lambda-shaped blocking response' do
          expect(described_class.on_finish({'statusCode' => 200})).to include(
            'statusCode' => 403,
            'headers' => {'Content-Type' => 'application/json'}
          )
        end

        it 'still records events and deactivates' do
          described_class.on_finish({'statusCode' => 200})

          aggregate_failures('cleanup after interrupt') do
            expect(Datadog::AppSec::Event).to have_received(:record)
            expect(appsec_context).to have_received(:export_metrics)
            expect(Datadog::AppSec::Context).to have_received(:deactivate)
          end
        end
      end

      context 'when an error occurs' do
        before do
          allow(gateway).to receive(:push).and_raise(StandardError, 'boom')
          described_class.on_finish({'statusCode' => 200})
        end

        it 'still deactivates the context' do
          expect(Datadog::AppSec::Context).to have_received(:deactivate)
        end
      end

      context 'when request-time override is clobbered by on_finish returning nil' do
        before do
          allow(Datadog::Utils).to receive(:send_end_invocation_request)
          allow(span).to receive_messages(id: 1, finish: nil)

          listener.instance_variable_set(:@response_override, {'statusCode' => 403})
          listener.instance_variable_set(:@trace, span)
          listener.on_end(response: {'statusCode' => 200}, request_context: request_context)
        end

        let(:listener) do
          Datadog::Trace::Listener.new(
            handler_name: 'handler', function_name: 'test',
            patch_http: false, merge_xray_traces: false
          )
        end
        let(:span) { instance_double(Datadog::Tracing::SpanOperation, set_metric: nil, set_tag: nil) }
        let(:request_context) do
          instance_double(
            'LambdaContext',
            invoked_function_arn: 'arn:aws:lambda:us-east-1:123:function:test',
            function_name: 'test',
            aws_request_id: 'req-1'
          )
        end

        it 'preserves request-time override after on_end with no response-time interrupt' do
          expect(listener.response_override).to include('statusCode' => 403)
        end
      end
    end
  end

  describe 'cross-invocation context cleanup' do
    context 'when on_start raises after activating context' do
      before do
        allow(Datadog::AppSec).to receive_messages(enabled?: true, security_engine: security_engine)
        allow(Datadog::AppSec::Context).to receive_messages(activate: nil, active: appsec_context, deactivate: nil)
        allow(Datadog::Lambda::AppSec::EventNormalizer).to receive(:normalize).and_raise(StandardError, 'bad event')

        described_class.on_start({'httpMethod' => 'GET', 'path' => '/'}, trace: trace, span: span)
      end

      let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
      let(:span) { instance_double(Datadog::Tracing::SpanOperation, set_metric: nil, set_tag: nil) }
      let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine::Engine, new_runner: waf_runner) }
      let(:waf_runner) { instance_double(Datadog::AppSec::SecurityEngine::Runner, ruleset_version: nil) }

      it 'deactivates context so next invocation gets a fresh one' do
        expect(Datadog::AppSec::Context).to have_received(:deactivate)
      end
    end
  end
end
