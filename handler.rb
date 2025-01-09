# frozen_string_literal: true

# Customer code lives here
LAMBDA_TASK_ROOT = ENV['LAMBDA_TASK_ROOT']

# Get the handler file and method from the environment
# file.method
LAMBDA_HANDLER = ENV['DD_LAMBDA_HANDLER']
handler_file, HANDLER_METHOD = LAMBDA_HANDLER.split('.')

# Add extension to the handler file
handler_file += '.rb'

begin
  handler_path = File.join(LAMBDA_TASK_ROOT, handler_file)

  raise LoadError, "Handler file not found at: #{handler_path}" unless File.exist?(handler_path)

  load(handler_path)
rescue LoadError => e
  puts "Failed to load handler file: #{e.message}"
  exit(1)
rescue SyntaxError => e
  puts "Syntax error in handler file: #{e.message}"
  exit(1)
rescue StandardError => e
  puts "Unexpected error while loading handler: #{e.class} - #{e.message}"
  exit(1)
end

require 'datadog/lambda'

Datadog::Lambda.configure_apm do |c|
  # Enable the instrumentation
end

def handler(event:, context:)
  Datadog::Lambda.wrap(event, context) do
    Kernel.send(HANDLER_METHOD, event:, context:)
  end
end
