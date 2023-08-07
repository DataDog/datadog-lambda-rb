# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#
# rubocop:disable Metrics/ModuleLength

require 'datadog/lambda/metrics'
require 'datadog/lambda/trace/listener'
require 'datadog/lambda/utils/logger'
require 'datadog/lambda/utils/extension'
require 'datadog/lambda/trace/patch_http'
require 'json'
require 'datadog/lambda/version'

module Datadog
  # Instruments AWS Lambda functions with Datadog distributed tracing and
  # custom metrics
  module Lambda
    @response = nil
    @is_cold_start = true
    @patch_http = true
    @metrics_client = Metrics::Client.instance

    # Configures Datadog's APM tracer with lambda specific defaults.
    # Same options can be given as Datadog.configure in tracer
    # See https://github.com/DataDog/dd-trace-rb/blob/master/docs/GettingStarted.md#quickstart-for-ruby-applications
    def self.configure_apm
      require 'datadog/tracing'
      require 'ddtrace/transport/io'

      @patch_http = false
      # Needed to keep trace flushes on a single line
      $stdout.sync = true

      Datadog.configure do |c|
        unless Datadog::Utils.extension_running?
          c.tracing.writer = Datadog::Tracing::SyncWriter.new(
            transport: Datadog::Transport::IO.default
          )
        end
        c.tags = { "_dd.origin": 'lambda' }
        # Enable AWS SDK instrumentation
        c.tracing.instrument :aws

        yield(c) if block_given?
      end
    end

    # Wrap the body of a lambda invocation
    # @param event [Object] event sent to lambda
    # @param context [Object] lambda context
    # @param block [Proc] implementation of the handler function.
    def self.wrap(event, context, &block)
      Datadog::Utils.update_log_level
      @listener ||= initialize_listener
      record_enhanced('invocations', context)
      begin
        cold = @is_cold_start
        @listener&.on_start(event: event, request_context: context, cold_start: cold)
        @response = block.call
      rescue StandardError => e
        record_enhanced('errors', context)
        raise e
      ensure
        @listener&.on_end(response: @response)
        @is_cold_start = false
        @metrics_client.close
      end
      @response
    end

    # Gets the current tracing context
    def self.trace_context
      Hash[Datadog::Trace.trace_context]
    end

    # Send a custom distribution metric
    # @param name [String] name of the metric
    # @param value [Numeric] value of the metric
    # @param time [Time] the time of the metric, should be in the past
    # @param tags [Hash] hash of tags, must be in "my.tag.name":"value" format
    def self.metric(name, value, time: nil, **tags)
      raise 'name must be a string' unless name.is_a?(String)
      raise 'value must be a number' unless value.is_a?(Numeric)

      @metrics_client.distribution(name, value, time: time, **tags)
    end

    def self.dd_lambda_layer_tag
      RUBY_VERSION[0, 3].tr('.', '')
    end

    # Generate tags for enhanced metrics
    # @param context [Object] https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    # @return [hash] a hash of the enhanced metrics tags
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.gen_enhanced_tags(context)
      arn_parts = context.invoked_function_arn.to_s.split(':')
      # Check if we have an alias or version
      function_alias = arn_parts[7].nil? ? nil : arn_parts[7]

      tags = {
        functionname: context.function_name,
        region: arn_parts[3],
        account_id: arn_parts[4],
        memorysize: context.memory_limit_in_mb,
        cold_start: @is_cold_start,
        runtime: "Ruby #{RUBY_VERSION}",
        resource: context.function_name,
        datadog_lambda: Datadog::Lambda::VERSION::STRING.to_sym
      }
      begin
        tags[:dd_trace] = Gem.loaded_specs['ddtrace'].version
      rescue StandardError
        Datadog::Utils.logger.debug 'dd-trace unavailable'
      end
      # If we have an alias...
      unless function_alias.nil?
        # If the alis version is $Latest, drop the $ for ddog tag convention.
        if function_alias.start_with?('$')
          function_alias[0] = ''
          # If the alias is not a version number add the executed version tag
        elsif !/\A\d+\z/.match(function_alias)
          tags[:executedversion] = context.function_version
        end
        # Append the alias to the resource tag
        tags[:resource] = context.function_name + ':' + function_alias
      end

      tags
    rescue StandardError => e
      Datadog::Utils.logger.error 'Unable to parse Lambda context' \
      "#{context}: #{e}"
      {}
    end

    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # Format and add tags to enhanced metrics
    # This method wraps the metric method, checking the DD_ENHANCED_METRICS
    # environment variable, adding 'aws.lambda.enhanced' to the metric name,
    # and adding the enhanced metric tags to the enhanced metrics.
    # @param metric_name [String] basic name of the metric
    # @param context [Object] AWS Ruby Lambda Context
    # @return [boolean] false if the metric was not added for some reason,
    #   true otherwise (for ease of testing

    def self.record_enhanced(metric_name, context)
      return false unless do_enhanced_metrics?

      etags = gen_enhanced_tags(context)
      metric("aws.lambda.enhanced.#{metric_name}", 1, **etags)
      true
    end

    # Check the DD_ENHANCED_METRICS environment variable
    # @return [boolean] true if this lambda should have
    # enhanced metrics
    def self.do_enhanced_metrics?
      dd_enhanced_metrics = ENV['DD_ENHANCED_METRICS']
      return true if dd_enhanced_metrics.nil?

      dd_enhanced_metrics.downcase == 'true'
    end

    def self.initialize_listener
      handler = ENV['_HANDLER'].nil? ? 'handler' : ENV['_HANDLER']
      function = ENV['AWS_LAMBDA_FUNCTION_NAME']
      merge_xray_traces = false
      merge_xray_traces_env = ENV['DD_MERGE_DATADOG_XRAY_TRACES']
      unless merge_xray_traces_env.nil?
        merge_xray_traces = merge_xray_traces_env.downcase == 'true'
        Datadog::Utils.logger.debug("Setting merge traces #{merge_xray_traces}")
      end

      # Only initialize listener if Tracing enabled.
      unless Datadog::Tracing.enabled?
        Datadog::Utils.logger.debug 'dd-trace unavailable'
        return nil
      end

      Trace::Listener.new(
        handler_name: handler,
        function_name: function,
        patch_http: @patch_http,
        merge_xray_traces: merge_xray_traces
      )
    end
  end
end
# rubocop:enable Metrics/ModuleLength
