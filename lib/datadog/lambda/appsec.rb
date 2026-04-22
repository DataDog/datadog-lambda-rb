# frozen_string_literal: true

require_relative 'appsec/request'

module Datadog
  module Lambda
    # AppSec integration for AWS Lambda invocations.
    module AppSec
      class << self
        def on_start(event, trace:, span:, inferred_span: nil)
          @request = nil
          @inferred_span = inferred_span
          return unless enabled?

          context = create_context(trace, span)
          return unless Datadog::AppSec::Context.active

          @request = Request.from_event(event)

          payload = Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(
            event, context: context
          )
          Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.request.start', payload)
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to start AppSec: #{e}"
        end

        def on_finish(response)
          return unless enabled?

          context = Datadog::AppSec::Context.active
          return unless context

          payload = Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(
            response, context: context
          )

          Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.response.start', payload)
          Datadog::AppSec::Event.record(context, request: @request)
          copy_appsec_span_tags(context.span, @inferred_span)

          context.export_metrics
          context.export_request_telemetry
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to finish AppSec: #{e}"
        ensure
          Datadog::AppSec::Context.deactivate if context
        end

        private

        def enabled?
          defined?(Datadog::AppSec) &&
            Datadog::AppSec.respond_to?(:enabled?) &&
            Datadog::AppSec.enabled?
        end

        # NOTE: _dd.appsec.json is required on both the service-entry span
        #       and the inferred span.
        def copy_appsec_span_tags(source_span, destination_span)
          return unless source_span && destination_span

          appsec_json = source_span.get_tag('_dd.appsec.json')
          destination_span.set_tag('_dd.appsec.json', appsec_json) if appsec_json

          appsec_enabled = source_span.get_metric('_dd.appsec.enabled')
          destination_span.set_metric('_dd.appsec.enabled', appsec_enabled) if appsec_enabled
        end

        def create_context(trace, span)
          return if trace.nil? || span.nil?

          security_engine = Datadog::AppSec.security_engine
          return unless security_engine

          context = Datadog::AppSec::Context.new(trace, span, security_engine.new_runner)
          Datadog::AppSec::Context.activate(context)

          span.set_metric(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)

          context
        end
      end
    end
  end
end
