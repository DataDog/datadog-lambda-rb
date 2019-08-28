# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

require 'datadog_lambda/trace/context'
require 'datadog_lambda/trace/xray_lambda'
require 'datadog_lambda/trace/patch_http'

require 'aws-xray-sdk'

module Datadog
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      def initialize
        XRay.recorder.configure(
          patch: %I[aws_sdk],
          context: Datadog::Trace::LambdaContext.new,
          streamer: Datadog::Trace::LambdaStreamer.new,
          emitter: Datadog::Trace::LambdaEmitter.new
        )
        Datadog::Trace.patch_http
      end

      def on_start(event:)
        trace_context = Datadog::Trace.extract_trace_context(event)
        Datadog::Trace.trace_context = trace_context
        Datadog::Utils.logger.debug "extracted trace context #{trace_context}"
      rescue StandardError => e
        Datadog::Utils.logger.error "couldn't read tracing context #{e}"
      end

      def on_end; end
    end
  end
end
