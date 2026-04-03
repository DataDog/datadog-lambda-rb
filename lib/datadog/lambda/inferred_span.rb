# frozen_string_literal: true

require_relative 'inferred_span/api_gateway_v1'
require_relative 'inferred_span/api_gateway_v2'

module Datadog
  module Lambda
    # Creates inferred spans representing upstream services
    # in the Lambda invocation path (e.g. API Gateway).
    #
    # @see https://docs.datadoghq.com/tracing/trace_collection/proxy_setup/apigateway/
    module InferredSpan
      EVENT_SOURCES = [ApiGatewayV1, ApiGatewayV2].freeze
      ARN_REGION_INDEX = 3
      ARN_SPLIT_LIMIT = 5

      class << self
        def create(event, request_context, trace_digest)
          klass = EVENT_SOURCES.find { |event_source| event_source.match?(event) }
          return unless klass

          start_span(klass.new(event), request_context: request_context, trace_digest: trace_digest)
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to create inferred span: #{e}"
          nil
        end

        private

        def start_span(event_source, request_context:, trace_digest:)
          resource = "#{event_source.method} #{event_source.resource_path}"

          tags = {
            'http.method' => event_source.method,
            'http.url' => http_url_for(event_source),
            'http.route' => event_source.resource_path,
            'endpoint' => event_source.path,
            'resource_names' => resource,
            'span.kind' => 'server',
            'apiid' => event_source.api_id,
            'apiname' => event_source.api_id,
            'stage' => event_source.stage,
            'request_id' => request_context.aws_request_id,
            '_inferred_span.synchronicity' => 'sync',
            '_inferred_span.tag_source' => 'self'
          }

          resource_key = resource_key_for(event_source, request_context)
          tags['dd_resource_key'] = resource_key if resource_key
          tags['http.useragent'] = event_source.user_agent if event_source.user_agent

          options = {
            service: event_source.domain.empty? ? nil : event_source.domain,
            resource: resource,
            type: 'web',
            tags: tags
          }
          options[:continue_from] = trace_digest if trace_digest
          options[:start_time] = ms_to_time(event_source.request_time_ms) if event_source.request_time_ms

          span = Datadog::Tracing.trace(event_source.span_name, **options)
          span.set_metric('_dd._inferred_span', 1.0)
          span
        end

        def http_url_for(event_source)
          return event_source.path if event_source.domain.empty?

          "https://#{event_source.domain}#{event_source.path}"
        end

        def resource_key_for(event_source, request_context)
          arn = request_context.invoked_function_arn.to_s
          return unless arn.include?(':')

          region = arn.split(':', ARN_SPLIT_LIMIT)[ARN_REGION_INDEX]
          return if event_source.api_id.empty? || event_source.stage.empty?

          "arn:aws:apigateway:#{region}::/#{event_source.arn_path_prefix}/#{event_source.api_id}/stages/#{event_source.stage}"
        end

        def ms_to_time(ms)
          Time.at(ms / 1000.0)
        end
      end
    end
  end
end
