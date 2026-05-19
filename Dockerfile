ARG image
FROM $image AS builder
ARG git_ref
ARG runtime
RUN echo "git_ref: $git_ref"
# Install dev dependencies
COPY . /ruby
WORKDIR /ruby
RUN apt-get update
RUN apt-get install -y gcc zip binutils

# Install this gem
RUN gem build datadog-lambda

# Install ddtrace gem
RUN gem install datadog-lambda --install-dir "/opt/ruby/gems/$runtime"
RUN set -eux; \
    if [ -z "${git_ref:-}" ]; then \
        # NOTE: datadog gem must be >= 2.24 to install on Ruby 4.0.x.
        gem install datadog -v 2.30 --install-dir "/opt/ruby/gems/$runtime"; \
    else \
        echo "building tracer from ref: $git_ref\n"; \
        git clone https://github.com/DataDog/dd-trace-rb.git --depth 1 --single-branch -b $git_ref /tmp/dd-trace-rb; \
        cd /tmp/dd-trace-rb; \
        gem build datadog.gemspec; \
        gem install ./datadog-*.gem --install-dir "/opt/ruby/gems/$runtime"; \
    fi

# Copy handler
COPY handler.rb /opt

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
