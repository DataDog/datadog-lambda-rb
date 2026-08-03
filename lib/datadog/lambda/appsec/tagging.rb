# frozen_string_literal: true

require 'json'

require 'datadog/tracing/client_ip'
require 'datadog/core/header_collection'
require 'datadog/appsec/default_header_tags'

module Datadog
  module Lambda
    module AppSec
      # Applies AppSec request, response, and keep-decision tags to the Lambda span
      module Tagging
        module_function

        def tag_request(request, context:)
          span = context.span
          return unless span

          headers = Datadog::Core::HeaderCollection.from_hash(request.headers)
          Datadog::AppSec::DefaultHeaderTags.tag_request(span, headers)

          return if span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP)

          Datadog::Tracing::ClientIp.set_client_ip_tag!(
            span, headers: headers, remote_ip: request.remote_addr
          )
        end

        def tag_response(response, context:)
          span = context.span
          return unless span

          headers = Datadog::Core::HeaderCollection.from_hash(response.headers)
          Datadog::AppSec::DefaultHeaderTags.tag_response(span, headers)

          return if headers.get('content-length')

          if (body = response.body)
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

          trace.keep!
          trace.set_tag(
            Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
            Datadog::Tracing::Sampling::Ext::Decision::ASM
          )
          span.set_tag(
            '_dd.appsec.event_rules.addresses', JSON.dump(context.waf_runner_known_addresses)
          )
        end
      end
    end
  end
end
