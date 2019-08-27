#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

# frozen_string_literal: true

require 'aws-xray-sdk'

module Datadog
  module Trace
    # Workaround to XRay not being supported in Lambda
    # https://github.com/aws/aws-xray-sdk-ruby/issues/20
    class LambdaStreamer < XRay::DefaultStreamer
      def initialize
        @stream_threshold = 1 # Stream every subsegment as it is available
      end
    end

    # LambdaEmitter filters out spans generated from the lambda daemon
    class LambdaEmitter < XRay::DefaultEmitter
      def should_send?(entity:)
        entity.name != '127.0.0.1' # Do not send localhost entities.
      end

      def send_entity(entity:)
        return nil unless should_send?(entity: entity)

        super
      end
    end

    # LambdaContext updated the trace id based on the curren trace header,
    # using a FacadeSegment
    class LambdaContext < XRay::DefaultContext
      def handle_context_missing
        nil
      end

      def check_context
        # Create a new FacadeSegment if the _X_AMZN_TRACE_ID changes.
        return if ENV['_X_AMZN_TRACE_ID'] == @current_trace_id

        # puts "XRAY: Starting new segment for #{ENV['_X_AMZN_TRACE_ID']}"
        @current_trace_id = ENV['_X_AMZN_TRACE_ID']
        trace_header = XRay::TraceHeader.from_header_string(
          header_str: @current_trace_id
        )
        segment = FacadeSegment.new(trace_id: trace_header.root,
                                    parent_id: trace_header.parent_id,
                                    id: trace_header.parent_id,
                                    name: 'lambda_context',
                                    sampled: trace_header.sampled)
        store_entity(entity: segment)
      end

      def current_entity
        # ensure the FacadeSegment is current whenever the current_entity is
        # retrieved
        check_context
        super
      end
    end

    # FacadeSegment is used to create a mock root span, that segments/
    # subsegments can be attached to. This span will never be submitted to the
    # X-Ray daemon
    class FacadeSegment < XRay::Segment
      def initialize(trace_id: nil, name: nil, parent_id: nil, id: nil,
                     sampled: true)
        super(trace_id: trace_id, name: name, parent_id: parent_id)
        @id = id
        @sampled = sampled
      end

      def ready_to_send?
        false # never send this facade.
      end
    end
  end
end
