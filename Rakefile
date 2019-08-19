# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'ddlambda/version'

task :build do
  system 'gem build ddlambda.gemspec'
end

task release: :build do
  system "gem push ddlambda-#{DDLambda::VERSION::STRING}"
end
