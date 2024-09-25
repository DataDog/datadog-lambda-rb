# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'datadog/lambda/version'

Gem::Specification.new do |spec|
  spec.name                  = 'datadog-lambda'
  spec.version               = Datadog::Lambda::VERSION::STRING
  spec.required_ruby_version = '>= 3.2.0'
  spec.authors               = ['Datadog, Inc.']
  spec.email                 = ['dev@datadoghq.com']

  spec.summary     = 'Instruments your Ruby AWS Lambda functions with Datadog'
  spec.description = <<-MSG.gsub(/^\s+/, '')
    datadog-lambda is Datadog's AWS Lambda integration for ruby. It is used to perform
    distributed tracing between serverful and serverless environments, and send
    custom metrics to Datadog.
  MSG

  spec.homepage = 'https://github.com/DataDog/datadog-lambda-rb'
  spec.license  = 'Apache-2.0'

  raise 'RubyGems 2.0 or newer required to protect against public gem pushes.' unless spec.respond_to?(:metadata)

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.files         = Dir.glob('lib/**/*')
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'aws-xray-sdk', '~> 0.11.3'
  spec.add_dependency 'dogstatsd-ruby', '~> 5.0'

  ruby_version = Gem::Version.new(RUBY_VERSION) # rubocop:disable Gemspec/RubyVersionGlobalsUsage
  if ruby_version >= Gem::Version.new('3.3')
    spec.add_dependency 'nokogiri', '~> 1.16.0'
  else
    spec.add_dependency 'nokogiri', '~> 1.15.6'
  end

  # We don't add this as a direct dependency, because it has
  # native modules that are difficult to package for lambda
  spec.add_development_dependency 'datadog', '~> 2.0'

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 12.3'
  spec.add_development_dependency 'rspec', '~> 3.8'
  spec.add_development_dependency 'rspec-collection_matchers', '~> 1.1'
  spec.add_development_dependency 'rubocop', '~> 1'
  spec.add_development_dependency 'solargraph', '~> 0.47.2'
end
