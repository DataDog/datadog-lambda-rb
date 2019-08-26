# frozen_string_literal: true

require 'aws-xray-sdk'

module DDLambda
  module Trace
    # Workaround to XRay not being supported in Lambda
    # https://github.com/aws/aws-xray-sdk-ruby/issues/20
    class LambdaStreamer < XRay::DefaultStreamer
      def initialize
        @stream_threshold = 1 # Stream every subsegment as it is available
      end
      end

    class LambdaEmitter < XRay::DefaultEmitter
      def should_send?(entity:)
        entity.name != '127.0.0.1' # Do not send localhost entities. It's the ruby lambda runtime
      end

      def send_entity(entity:)
        return nil unless should_send?(entity: entity)

        super
      end
    end

    class LambdaContext < XRay::DefaultContext
      def handle_context_missing
        nil
      end

      def check_context
        # Create a new FacadeSegment if the _X_AMZN_TRACE_ID changes.
        if ENV['_X_AMZN_TRACE_ID'] != @current_trace_id
          # puts "XRAY: Starting new segment for #{ENV['_X_AMZN_TRACE_ID']}"
          @current_trace_id = ENV['_X_AMZN_TRACE_ID']
          trace_header = XRay::TraceHeader.from_header_string(header_str: @current_trace_id)
          segment = FacadeSegment.new(trace_id: trace_header.root,
                                      parent_id: trace_header.parent_id,
                                      id: trace_header.parent_id,
                                      name: 'lambda_context',
                                      sampled: trace_header.sampled)
          store_entity(entity: segment)
        end
      end

      def current_entity
        check_context # ensure the FacadeSegment is current whenever the current_entity is retrieved
        super
      end
    end

    class FacadeSegment < XRay::Segment
      def initialize(trace_id: nil, name: nil, parent_id: nil, id: nil, sampled: true)
        super(trace_id: trace_id, name: name, parent_id: parent_id)
        @id = id
        @sampled = sampled
      end

      def ready_to_send?
        false # never send this facade. AWS Lambda has already created a Segment with these ids
      end
    end
  end
end
