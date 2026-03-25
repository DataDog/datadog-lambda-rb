# frozen_string_literal: true

module Datadog
  module Lambda
    module InferredSpan
      class << self
        def create(event, request_context, trace_digest)
          return unless managed_services_enabled?

          span_name = inferred_span_name(event)
          return unless span_name

          rc = event['requestContext'] || {}
          domain = rc['domainName'] || ''
          api_id = rc['apiId'] || ''
          stage = rc['stage'] || ''

          if span_name == 'aws.apigateway'
            method = event['httpMethod']
            path = event['path'] || '/'
            resource_path = rc['resourcePath'] || path
            request_time_ms = rc['requestTimeEpoch']
            user_agent = rc.dig('identity', 'userAgent')
          else
            http = rc['http'] || {}
            method = http['method']
            path = event['rawPath'] || '/'
            resource_path = event['routeKey']&.sub(/^[A-Z]+ /, '') || path
            request_time_ms = rc['timeEpoch']
            user_agent = http['userAgent']
          end

          resource = "#{method} #{resource_path}"
          http_url = domain.empty? ? path : "https://#{domain}#{path}"

          tags = {
            'http.method' => method,
            'http.url' => http_url,
            'http.route' => resource_path,
            'endpoint' => path,
            'resource_names' => resource,
            'span.kind' => 'server',
            'apiid' => api_id,
            'apiname' => api_id,
            'stage' => stage,
            'request_id' => request_context.aws_request_id,
            '_inferred_span.synchronicity' => 'sync',
            '_inferred_span.tag_source' => 'self',
          }

          arn = request_context.invoked_function_arn.to_s
          region = arn.split(':')[3] if arn.include?(':')
          if region && !api_id.empty? && !stage.empty?
            arn_path = span_name == 'aws.apigateway' ? 'restapis' : 'apis'
            tags['dd_resource_key'] = "arn:aws:apigateway:#{region}::/#{arn_path}/#{api_id}/stages/#{stage}"
          end

          tags['http.useragent'] = user_agent if user_agent

          inferred_options = {
            service: domain.empty? ? nil : domain,
            resource: resource,
            type: 'web',
            tags: tags,
          }
          inferred_options[:continue_from] = trace_digest if trace_digest
          inferred_options[:start_time] = Time.at(request_time_ms / 1000.0) if request_time_ms

          span = Datadog::Tracing.trace(span_name, **inferred_options)
          span.set_metric('_dd._inferred_span', 1.0)
          span
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to create inferred span: #{e}"
          nil
        end

        def finish(inferred_span, response)
          return unless inferred_span

          status_code = extract_status_code(response)
          inferred_span.set_tag('http.status_code', status_code.to_s) if status_code

          inferred_span.finish
        rescue StandardError => e
          Datadog::Utils.logger.debug "failed to finish inferred span: #{e}"
        end

        private

        def inferred_span_name(event)
          return unless event.is_a?(Hash)

          rc = event['requestContext']
          return unless rc.is_a?(Hash) && rc['stage']

          if event['httpMethod']
            'aws.apigateway'
          elsif event['routeKey']
            'aws.httpapi'
          end
        end

        def managed_services_enabled?
          Datadog::Lambda.trace_managed_services?
        end

        def extract_status_code(response)
          return unless response.is_a?(Hash)

          response['statusCode']
        end
      end
    end
  end
end
