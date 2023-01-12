require 'yaml'

creds = "#{Dir.home}/.gem/credentials"

unless File.exist? creds
    puts "%s does not exist. Please get the Datadog-Lambda-Ruby RubyGems API Key from the Serverless shared 1Password vault." % [creds]
    exit 1
end

creds_file = File.open creds

creds_dict = YAML.load creds_file.read

creds_file.close

api_key = creds_dict[:rubygems_api_key]

if api_key.start_with? "rubygems_7"
    puts "It looks like the API key in %s is the old API key. Please get the Datadog-Lambda-Ruby RubyGems API Key from the Serverless shared 1password vault." % [creds]
    exit 1
end