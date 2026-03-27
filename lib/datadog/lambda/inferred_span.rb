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
      PARSERS = [ApiGatewayV1, ApiGatewayV2].freeze

      class << self
        def create(event, request_context, trace_digest)
          klass = PARSERS.find { |parser| parser.match?(event) }
          return unless klass

          build_span(klass.new(event), request_context, trace_digest)
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to create inferred span: #{e}"
          nil
        end

        private

        def build_span(parser, request_context, trace_digest)
          resource = "#{parser.method} #{parser.resource_path}"
          domain = parser.domain
          http_url = domain.empty? ? parser.path : "https://#{domain}#{parser.path}"

          tags = {
            'http.method' => parser.method,
            'http.url' => http_url,
            'http.route' => parser.resource_path,
            'endpoint' => parser.path,
            'resource_names' => resource,
            'span.kind' => 'server',
            'apiid' => parser.api_id,
            'apiname' => parser.api_id,
            'stage' => parser.stage,
            'request_id' => request_context.aws_request_id,
            '_inferred_span.synchronicity' => 'sync',
            '_inferred_span.tag_source' => 'self',
          }

          arn = request_context.invoked_function_arn.to_s
          region = arn.split(':')[3] if arn.include?(':')
          if region && !parser.api_id.empty? && !parser.stage.empty?
            tags['dd_resource_key'] = "arn:aws:apigateway:#{region}::/#{parser.arn_path_prefix}/#{parser.api_id}/stages/#{parser.stage}"
          end

          tags['http.useragent'] = parser.user_agent if parser.user_agent

          options = {
            service: domain.empty? ? nil : domain,
            resource: resource,
            type: 'web',
            tags: tags,
          }
          options[:continue_from] = trace_digest if trace_digest
          options[:start_time] = Time.at(parser.request_time_ms / 1000.0) if parser.request_time_ms

          span = Datadog::Tracing.trace(parser.span_name, **options)
          span.set_metric('_dd._inferred_span', 1.0)
          span
        end

      end
    end
  end
end
