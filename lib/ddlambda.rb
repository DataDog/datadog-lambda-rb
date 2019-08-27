# frozen_string_literal: true

require 'ddlambda/trace/listener'
require 'ddlambda/utils/logger'
require 'ddlambda/trace/patch_http'
require 'json'
require 'time'

# Datadog instruments AWS Lambda functions with Datadog distributed tracing and
# custom metrics
module DDLambda
  # Wrap the body of a lambda invocation
  # @param event [Object] event sent to lambda
  # @param context [Object] lambda context
  # @param block [Proc] implementation of the handler function.
  def self.wrap(event, _context, &block)
    DDLambda::Utils.update_log_level

    @listener ||= Trace::Listener.new
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
    DDLambda::Trace.trace_context
  end

  # Send a custom distribution metric
  # @param name [String] name of the metric
  # @param value [Numeric] value of the metric
  # @param time [Time] the time of the metric, should be in the past
  # @param tags [Hash] hash of tags, must be in "my.tag.name":"value" format
  def self.metric(name, value, time: nil, **tags)
    raise 'name must be a string' unless name.is_a?(String)
    raise 'value must be a number' unless value.is_a?(Numeric)

    time ||= Time.now
    tag_list = []
    tags.each do |tag|
      tag_list.push("#{tag[0]}:#{tag[1]}")
    end
    time_ms = (time.to_f * 100).to_i
    metric = { e: time_ms, m: name, t: tag_list, v: value }.to_json
    puts metric
  end
end
