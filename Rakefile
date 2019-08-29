# frozen_string_literal: true

require 'rspec/core/rake_task'

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'datadog/lambda/version'

task :build do
  system 'gem build datadog-lambda.gemspec'
end

task release: :build do
  system "gem push datadog-lambda-#{Datadog::Lambda::VERSION::STRING}"
end

RSpec::Core::RakeTask.new(:test) do |t|
  t.pattern = 'test/**/*\.spec\.rb'
end
