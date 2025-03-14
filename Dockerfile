ARG image
FROM $image AS builder
ARG runtime
# Install dev dependencies
COPY . /var/task/datadog-lambda-rb
WORKDIR /var/task/datadog-lambda-rb
RUN apt-get update
RUN apt-get install -y gcc zip binutils

# Install this gem
RUN gem build datadog-lambda

# Install ddtrace gem
RUN gem install datadog-lambda --install-dir "/opt/ruby/gems/$runtime"
RUN gem install datadog -v 2.12 --install-dir "/opt/ruby/gems/$runtime"

WORKDIR /opt
# Remove native extension debase-ruby_core_source (25MB) runtimes below Ruby 2.6
RUN rm -rf ./ruby/gems/$runtime/gems/debase-ruby_core_source*/
# Remove aws-sdk related (2MB), included in runtime
RUN rm -rf ./ruby/gems/$runtime/gems/aws*/
# Remove binaries not needed in AWS Lambda
RUN find . -name '*linux-musl*' -prune -exec rm -rf {} +

# Cache files zipped gem files, that aren't used by during runtime, only during 
# installation, so they are safe to delete
RUN rm -rf "/opt/ruby/gems/${runtime}/cache"
RUN cd /opt

FROM scratch
COPY --from=builder /opt /
