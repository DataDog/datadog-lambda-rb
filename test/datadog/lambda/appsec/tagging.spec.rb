# frozen_string_literal: true

require 'datadog/lambda'
require 'datadog/lambda/appsec/tagging'

RSpec.describe Datadog::Lambda::AppSec::Tagging do
  before do
    stub_const('Datadog::AppSec::WAF::VERSION::BASE_STRING', '1.30.0')

    allow(Datadog::AppSec::DefaultHeaderTags).to receive(:tag_request)
    allow(Datadog::AppSec::DefaultHeaderTags).to receive(:tag_response)
    allow(Datadog::Tracing::ClientIp).to receive(:set_client_ip_tag!)
  end

  let(:span) do
    instance_double(Datadog::Tracing::SpanOperation, set_tag: nil, set_metric: nil, get_tag: nil)
  end
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation, keep!: nil, set_tag: nil) }
  let(:context) do
    instance_double(
      Datadog::AppSec::Context,
      span: span, trace: trace,
      waf_runner_ruleset_version: '1.12.0',
      waf_runner_known_addresses: ['server.request.headers.no_cookies']
    )
  end

  describe '.tag_request' do
    subject(:tag_request) { described_class.tag_request(request, context: context) }

    let(:request) do
      instance_double(
        Datadog::Lambda::AppSec::Request,
        headers: {'user-agent' => 'TestBot'}, remote_addr: '1.2.3.4'
      )
    end

    it 'applies default request header tags' do
      tag_request

      expect(Datadog::AppSec::DefaultHeaderTags).to have_received(:tag_request).with(
        span, kind_of(Datadog::Core::HeaderCollection)
      )
    end

    it 'sets the client IP tag from the remote address' do
      tag_request

      expect(Datadog::Tracing::ClientIp).to have_received(:set_client_ip_tag!).with(
        span, headers: kind_of(Datadog::Core::HeaderCollection), remote_ip: '1.2.3.4'
      )
    end

    context 'when the client IP tag is already set' do
      before do
        allow(span).to receive(:get_tag)
          .with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP).and_return('9.9.9.9')
      end

      it 'does not overwrite the client IP tag' do
        tag_request

        expect(Datadog::Tracing::ClientIp).not_to have_received(:set_client_ip_tag!)
      end
    end

    context 'when the span is missing' do
      before { allow(context).to receive(:span).and_return(nil) }

      it 'does not tag anything' do
        tag_request

        expect(Datadog::AppSec::DefaultHeaderTags).not_to have_received(:tag_request)
      end
    end
  end

  describe '.tag_response' do
    subject(:tag_response) { described_class.tag_response(response, context: context) }

    let(:response) do
      instance_double(
        Datadog::Lambda::AppSec::Response,
        headers: {'content-type' => 'text/html'}, body: 'hello'
      )
    end

    it 'applies default response header tags' do
      tag_response

      expect(Datadog::AppSec::DefaultHeaderTags).to have_received(:tag_response).with(
        span, kind_of(Datadog::Core::HeaderCollection)
      )
    end

    it 'sets content-length from the body byte size' do
      tag_response

      expect(span).to have_received(:set_tag).with('http.response.headers.content-length', '5')
    end

    context 'when a content-length header is present' do
      let(:response) do
        instance_double(
          Datadog::Lambda::AppSec::Response,
          headers: {'content-length' => '10'}, body: 'hello'
        )
      end

      it 'does not derive content-length from the body' do
        tag_response

        expect(span).not_to have_received(:set_tag).with('http.response.headers.content-length', anything)
      end
    end

    context 'when the span is missing' do
      before { allow(context).to receive(:span).and_return(nil) }

      it 'does not tag anything' do
        tag_response

        expect(Datadog::AppSec::DefaultHeaderTags).not_to have_received(:tag_response)
      end
    end
  end

  describe '.tag_and_keep' do
    subject(:tag_and_keep) { described_class.tag_and_keep(context, cold_start: false) }

    it 'marks the span as appsec-enabled with runtime and WAF version' do
      tag_and_keep

      aggregate_failures('appsec span tags') do
        expect(span).to have_received(:set_metric).with(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
        expect(span).to have_received(:set_tag).with('_dd.runtime_family', 'ruby')
        expect(span).to have_received(:set_tag).with('_dd.appsec.waf.version', '1.30.0')
      end
    end

    it 'sets the event rules version from the WAF runner' do
      tag_and_keep

      expect(span).to have_received(:set_tag).with('_dd.appsec.event_rules.version', '1.12.0')
    end

    it 'does not keep the trace on a warm start' do
      tag_and_keep

      aggregate_failures('no cold start tags') do
        expect(trace).not_to have_received(:keep!)
        expect(span).not_to have_received(:set_tag).with('_dd.appsec.event_rules.addresses', anything)
      end
    end

    context 'when the ruleset version is not set' do
      before { allow(context).to receive(:waf_runner_ruleset_version).and_return(nil) }

      it 'skips the event rules tags' do
        tag_and_keep

        expect(span).not_to have_received(:set_tag).with('_dd.appsec.event_rules.version', anything)
      end
    end

    context 'when cold_start is true' do
      subject(:tag_and_keep) { described_class.tag_and_keep(context, cold_start: true) }

      it 'keeps the trace and records known addresses' do
        tag_and_keep

        aggregate_failures('cold start tags') do
          expect(trace).to have_received(:keep!)
          expect(trace).to have_received(:set_tag).with(
            Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
            Datadog::Tracing::Sampling::Ext::Decision::ASM
          )
          expect(span).to have_received(:set_tag).with(
            '_dd.appsec.event_rules.addresses', '["server.request.headers.no_cookies"]'
          )
        end
      end
    end

    context 'when the trace is missing' do
      before { allow(context).to receive(:trace).and_return(nil) }

      it 'does not tag anything' do
        tag_and_keep

        expect(span).not_to have_received(:set_metric)
      end
    end
  end
end
