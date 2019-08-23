# frozen_string_literal: true

require 'ddlambda/trace/listener'

# Datadog instruments AWS Lambda functions with Datadog distributed tracing and
# custom metrics
module DDLambda
  @listener = nil

  # Wrap the body of a lambda invocation
  # @param event [Object] event sent to lambda
  # @param context [Object] lambda context
  # @param block [Proc] implementation of the handler function.
  def self.wrap(event, _context, &block)
    @listener = Trace::Listener.new if @listener.nil?
    @listener.on_start(event: event)
    begin
      res = block.call
    ensure
      @listener.on_end
    end
    res
  end

  # Gets the current tracing context
  def self.trace_context
    @listener&.context
  end
end
