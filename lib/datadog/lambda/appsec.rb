# frozen_string_literal: true

require 'datadog/appsec/api_security'

require_relative 'appsec/tagging'
require_relative 'appsec/request'
require_relative 'appsec/response'
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

          Tagging.tag_and_keep(context, cold_start: cold_start)

          event = EventNormalizer.normalize(event)
          @request = Request.from_normalized(event)

          Tagging.tag_request(@request, context: context)
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

          normalized = ResponseNormalizer.normalize(response)
          response = Response.from_normalized(normalized)

          interrupt_params = nil
          unless context.interrupted?
            Tagging.tag_response(response, context: context)
            payload = Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(
              normalized, context: context
            )

            interrupt_params = catch(Datadog::AppSec::Ext::INTERRUPT) do
              Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.response.start', payload)
              nil
            end

            context.mark_as_interrupted! if interrupt_params
          end

          extract_api_security_schema(context, request: @request, response: response)

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

        def catch_interrupt
          interrupt_params = catch(Datadog::AppSec::Ext::INTERRUPT) do
            return yield
          end

          if (context = Datadog::AppSec::Context.active)
            context.mark_as_interrupted!
          end

          response_override(interrupt_params, headers: @request.headers)
        end

        private

        def extract_api_security_schema(context, request:, response:)
          return unless request && response

          if Datadog::AppSec::APISecurity.enabled? &&
             Datadog::AppSec::APISecurity.sample_trace?(context.trace) &&
             Datadog::AppSec::APISecurity.sample?(request, response)
            context.extract_schema!
          end
        end

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
