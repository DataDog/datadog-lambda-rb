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

  spec.summary     = 'Adds Datadog instrumentation to your Ruby AWS Lambda functions'
  spec.description = <<-EOS.gsub(/^[\s]+/, '')
    ddlambda is Datadog’s AWS Lambda integration for ruby. It is used to perform distributed
    tracing between serverful and serverless environments, and send custom metrics to Datadog.
  EOS

  spec.homepage = 'https://github.com/DataDog/dd-lambda-rb'
  spec.license  = 'Apache-2.0'

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 12.3'
  spec.add_development_dependency 'rubocop', '~> 0.74'
  spec.add_development_dependency 'rspec', '~> 3.8'
  spec.add_development_dependency 'rspec-collection_matchers', '~> 1.1'
end
