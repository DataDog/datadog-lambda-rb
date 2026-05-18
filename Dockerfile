ARG image
FROM $image AS builder
ARG git_ref
ARG runtime
RUN echo "git_ref: $git_ref"
# Install dev dependencies
COPY . /var/task/datadog-lambda-rb
WORKDIR /var/task/datadog-lambda-rb

# NOTE: AL2 (Ruby 3.2) uses yum, AL2023 (Ruby 3.3+) uses dnf
RUN PKG=$(command -v dnf || command -v yum) && \
    $PKG install -y gcc gcc-c++ make zip binutils libffi-devel

# Install this gem
RUN gem build datadog-lambda

# Install ddtrace gem
RUN gem install datadog-lambda --install-dir "/opt/ruby/gems/$runtime"
RUN set -eux; \
    if [ -z "${git_ref:-}" ]; then \
        # NOTE: datadog gem must be >= 2.24 to install on Ruby 4.0.x.
        MAKEFLAGS="-j$(nproc)" \
        gem install datadog -v 2.33 --install-dir "/opt/ruby/gems/$runtime" --no-document; \
    else \
        echo "building tracer from ref: $git_ref\n"; \
        git clone https://github.com/DataDog/dd-trace-rb.git --depth 1 --single-branch -b $git_ref /tmp/dd-trace-rb; \
        cd /tmp/dd-trace-rb; \
        gem build datadog.gemspec; \
        gem install ./datadog-*.gem --install-dir "/opt/ruby/gems/$runtime"; \
    fi


# Recompile FFI from source — precompiled binaries have glibc mismatch with Lambda AL2
#
# NOTE: runs after datadog gem as a defensive measure — force-replaces whatever
#       transitive FFI variant was pulled, regardless of version resolution.
RUN MAKEFLAGS="-j$(nproc)" \
gem install ffi -v 1.17.4 --platform ruby --force --install-dir "/opt/ruby/gems/$runtime" --no-document
RUN rm -rf /opt/ruby/gems/$runtime/gems/ffi-*-*-linux-* \
       /opt/ruby/gems/$runtime/specifications/ffi-*-*-linux-*.gemspec

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
