# frozen_string_literal: true

require 'yaml'

creds = "#{Dir.home}/.gem/credentials"

unless File.exist? creds
  puts format('%s does not exist. " + \
  "Please get the Datadog-Lambda-Ruby RubyGems API Key from the Serverless shared 1Password vault.', creds)
  exit 1
end

creds_file = File.open creds

creds_dict = YAML.safe_load(creds_file.read, permitted_classes: [Hash, String, Symbol], symbolize_names: true)

creds_file.close

api_key = creds_dict[:rubygems_api_key]

if api_key.start_with? 'rubygems_7'
  puts format('It looks like the API key in %s is the old API key. " + \
  "Please get the Datadog-Lambda-Ruby RubyGems API Key from the Serverless shared 1password vault.', creds)
  exit 1
end
