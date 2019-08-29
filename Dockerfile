ARG image
FROM $image
ARG runtime

# Install dev dependencies
COPY . datadog-lambda-ruby
WORKDIR /datadog-lambda-ruby
RUN gem build datadog-lambda
RUN gem install datadog-lambda --install-dir "/ruby/gems/${runtime}"
# Cache files zipped gem files, that aren't used by during runtime, only during 
# installation, so they are safe to delete
RUN rm -rf "/ruby/gems/${runtime}/cache"
