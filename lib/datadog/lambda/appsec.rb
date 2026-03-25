# frozen_string_literal: true

module Datadog
  module Lambda
    module AppSec
      class << self
        def on_start(event, trace, span)
          return unless enabled?

          Datadog.configuration.appsec.instrument(:aws_lambda)

          trace ||= Datadog::Tracing.active_trace
          span ||= Datadog::Tracing.active_span

          create_context(trace, span)

          Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.request.start', event)
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to start AppSec: #{e}"
        end

        def on_finish(response)
          context = Datadog::AppSec::Context.active
          return unless context

          Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.response.start', response)

          Datadog::AppSec::Event.record(context, request: context.state[:request])

          context.export_metrics
          context.export_request_telemetry
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to finish AppSec: #{e}"
        ensure
          Datadog::AppSec::Context.deactivate
        end

        private

        def enabled?
          defined?(Datadog::AppSec) &&
            Datadog::AppSec.respond_to?(:enabled?) &&
            Datadog::AppSec.enabled?
        end

        def create_context(trace, span)
          security_engine = Datadog::AppSec.security_engine
          return unless security_engine
          return if trace.nil? || span.nil?

          Datadog::AppSec::Context.activate(
            Datadog::AppSec::Context.new(trace, span, security_engine.new_runner)
          )

          span.set_metric(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
        end
      end
    end
  end
end
