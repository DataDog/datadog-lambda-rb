# frozen_string_literal: true

require 'rspec/core/rake_task'

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'datadog_lambda/version'

task :build do
  system 'gem build datadog_lambda.gemspec'
end

task release: :build do
  system "gem push datadog_lambda-#{DDLambda::VERSION::STRING}"
end

RSpec::Core::RakeTask.new(:test) do |t|
  t.pattern = 'test/**/*\.spec\.rb'
end
