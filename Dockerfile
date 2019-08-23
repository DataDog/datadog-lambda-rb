ARG image
FROM $image
ARG runtime

# Install dev dependencies
COPY . datadog-lambda-ruby
WORKDIR /datadog-lambda-ruby
RUN gem build ddlambda
RUN gem install ddlambda --install-dir "/ruby/gems/${runtime}"
# Cache files zipped gem files, that aren't used by during runtime, only during 
# installation, so they are safe to delete
RUN rm -rf "/ruby/gems/${runtime}/cache"
