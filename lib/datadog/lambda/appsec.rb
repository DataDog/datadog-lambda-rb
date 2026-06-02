# frozen_string_literal: true

require 'json'

require 'datadog/tracing/client_ip'
require 'datadog/core/header_collection'
require 'datadog/appsec/default_header_tags'

require_relative 'appsec/request'
require_relative 'appsec/event_normalizer'
require_relative 'appsec/response_normalizer'

module Datadog
  module Lambda
    # AppSec integration for AWS Lambda invocations.
    module AppSec
      class << self
        # rubocop:disable Metrics/AbcSize
        def on_start(event, trace:, span:, cold_start: false)
          @request = nil
          return unless enabled?

          context = create_context(trace, span)
          return unless Datadog::AppSec::Context.active

          tag_and_keep(context, cold_start: cold_start)

          event = EventNormalizer.normalize(event)
          @request = Request.from_normalized(event)

          add_request_tags(context, @request)
          payload = Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(
            event, context: context
          )

          interrupt_params = catch(Datadog::AppSec::Ext::INTERRUPT) do
            Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.request.start', payload)
            nil
          end

          return unless interrupt_params

          context.mark_as_interrupted!
          response_override(interrupt_params, headers: @request.headers)
        rescue StandardError => e
          Datadog::AppSec::Context.deactivate if context
          Datadog::Utils.logger.debug("failed to start AppSec: #{e}")
        end
        # rubocop:enable Metrics/AbcSize

        # rubocop:disable Metrics/AbcSize
        def on_finish(response)
          return unless enabled?

          context = Datadog::AppSec::Context.active
          return unless context

          response = ResponseNormalizer.normalize(response)

          add_response_tags(context, response)
          payload = Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(
            response, context: context
          )

          interrupt_params = catch(Datadog::AppSec::Ext::INTERRUPT) do
            Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.response.start', payload)
            nil
          end

          context.mark_as_interrupted! if interrupt_params

          Datadog::AppSec::Event.record(context, request: @request)
          context.export_metrics
          context.export_request_telemetry

          response_override(interrupt_params, headers: @request.headers) if interrupt_params
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to finish AppSec: #{e}"
        ensure
          Datadog::AppSec::Context.deactivate if context
        end
        # rubocop:enable Metrics/AbcSize

        private

        def enabled?
          defined?(Datadog::AppSec) &&
            Datadog::AppSec.respond_to?(:enabled?) &&
            Datadog::AppSec.enabled?
        end

        def create_context(trace, span)
          return if trace.nil? || span.nil?

          security_engine = Datadog::AppSec.security_engine
          return unless security_engine

          context = Datadog::AppSec::Context.new(trace, span, security_engine.new_runner)
          Datadog::AppSec::Context.activate(context)

          context
        end

        def add_request_tags(context, request)
          span = context.span
          return unless span

          headers = Datadog::Core::HeaderCollection.from_hash(request.headers)
          Datadog::AppSec::DefaultHeaderTags.tag_request(span, headers)

          return if span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP)

          Datadog::Tracing::ClientIp.set_client_ip_tag!(
            span, headers: headers, remote_ip: request.remote_addr
          )
        end

        def add_response_tags(context, response)
          span = context.span
          return unless span

          headers = Datadog::Core::HeaderCollection.from_hash(response['headers'] || {})
          Datadog::AppSec::DefaultHeaderTags.tag_response(span, headers)

          return if headers.get('content-length')

          if (body = response['body'])
            span.set_tag('http.response.headers.content-length', body.bytesize.to_s)
          end
        end

        def tag_and_keep(context, cold_start:)
          span = context.span
          trace = context.trace

          return unless trace && span

          span.set_metric(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
          span.set_tag('_dd.runtime_family', 'ruby')
          span.set_tag('_dd.appsec.waf.version', Datadog::AppSec::WAF::VERSION::BASE_STRING)

          ruleset_version = context.waf_runner_ruleset_version
          return unless ruleset_version

          span.set_tag('_dd.appsec.event_rules.version', ruleset_version)

          return unless cold_start

          span.set_tag(
            '_dd.appsec.event_rules.addresses', JSON.dump(context.waf_runner_known_addresses)
          )

          trace.keep!
          trace.set_tag(
            Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
            Datadog::Tracing::Sampling::Ext::Decision::ASM
          )
        end

        def response_override(interrupt_params, headers:)
          response = Datadog::AppSec::Response.from_interrupt_params(
            interrupt_params, headers['accept']
          )

          {
            'statusCode' => response.status,
            'headers' => response.headers,
            'body' => response.body.join
          }
        end
      end
    end
  end
end
