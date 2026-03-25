# frozen_string_literal: true

module Datadog
  module Trace
    module LambdaAppSec
      class << self
        def start(event)
          return unless enabled?

          ensure_patched

          Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.request.start', event)
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to start AppSec: #{e}"
        end

        def finish(response)
          return unless Datadog::AppSec::Context.active

          Datadog::AppSec::Instrumentation.gateway.push('aws_lambda.response.start', response)
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to finish AppSec: #{e}"
        end

        private

        def enabled?
          defined?(Datadog::AppSec) &&
            Datadog::AppSec.respond_to?(:enabled?) &&
            Datadog::AppSec.enabled?
        end

        def ensure_patched
          return if @patched

          Datadog.configuration.appsec.instrument(:aws_lambda)
          @patched = true
        end
      end
    end
  end
end
