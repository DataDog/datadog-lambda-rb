# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

task default: :test

RSpec::Core::RakeTask.new(:test) do |t|
  t.pattern = 'test/**/*\.spec\.rb'
end
