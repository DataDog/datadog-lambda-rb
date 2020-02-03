ARG image
FROM $image
ARG runtime
# Install dev dependencies
COPY . /var/task/datadog-lambda-ruby
WORKDIR /var/task/datadog-lambda-ruby
RUN gem build datadog-lambda
RUN gem install datadog-lambda --install-dir "/opt/ruby/gems/${runtime}"
# Cache files zipped gem files, that aren't used by during runtime, only during 
# installation, so they are safe to delete
RUN rm -rf "/opt/ruby/gems/${runtime}/cache"
RUN cd /opt