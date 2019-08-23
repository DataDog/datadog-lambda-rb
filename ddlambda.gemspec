# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddlambda/version'

Gem::Specification.new do |spec|
  spec.name                  = 'ddlambda'
  spec.version               = DDLambda::VERSION::STRING
  spec.required_ruby_version = '>= 2.5.0'
  spec.authors               = ['Datadog, Inc.']
  spec.email                 = ['dev@datadoghq.com']

  spec.summary     = 'Instruments your Ruby AWS Lambda functions with Datadog'
  spec.description = <<-MSG.gsub(/^[\s]+/, '')
    ddlambda is Datadog’s AWS Lambda integration for ruby. It is used to perform
    distributed tracing between serverful and serverless environments, and send
    custom metrics to Datadog.
  MSG

  spec.homepage = 'https://github.com/DataDog/dd-lambda-rb'
  spec.license  = 'Apache-2.0'

  unless spec.respond_to?(:metadata)
    raise 'RubyGems 2.0 or newer required to protect against public gem pushes.'
  end

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.files         = Dir.glob('lib/**/*')
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'aws-xray-sdk', '~> 0.11'

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 12.3'
  spec.add_development_dependency 'rspec', '~> 3.8'
  spec.add_development_dependency 'rspec-collection_matchers', '~> 1.1'
  spec.add_development_dependency 'rubocop', '~> 0.74'
end
