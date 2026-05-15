ARG image
FROM $image AS builder
ARG git_ref
ARG runtime
RUN echo "git_ref: $git_ref"
# Install dev dependencies
COPY . /var/task/datadog-lambda-rb
WORKDIR /var/task/datadog-lambda-rb
RUN apt-get update
# `libffi-dev` + `make` are needed to compile the `ffi` gem from source
# below — see the rebuild step after the datadog gem install.
RUN apt-get install -y gcc zip binutils make libffi-dev pkg-config

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

# Force `ffi` to be (re)built from source in this per-runtime builder so
# the resulting `ffi_c.so` matches the target Lambda runtime's Ruby ABI
# exactly. The precompiled `ffi-x.y.z-x86_64-linux-gnu` gem shipped via
# rubygems ships ABI-specific subdirs (`lib/3.3/ffi_c.so`,
# `lib/3.4/ffi_c.so`, …) and `ffi 1.17` does NOT include a Ruby 3.2
# subdir. Without this step, dd-trace-rb 2.30's AppSec component (which
# `require`s libddwaf → ffi → ffi_c) crashes the function at boot on
# Ruby 3.2 when `DD_APPSEC_ENABLED=true`:
#
#     Init<LoadError>: cannot load such file -- ffi_c
#
# Confirmed via a single-lambda sandbox repro on 2026-05-15
# (datadog-lambda-rb v3.28.0, Datadog-Ruby3-2:28 + DD_APPSEC_ENABLED=true).
# Same combo on Ruby 3.4 / 4.0 works because the precompiled package does
# bundle binaries for their ABIs, but compiling from source here is a
# permanent fix that's defensive against future `ffi` releases dropping
# additional Ruby ABIs from the precompiled bundle.
RUN set -eux; \
    gem uninstall ffi --all --ignore-dependencies --executables --force \
        --install-dir "/opt/ruby/gems/$runtime" || true; \
    gem install ffi --platform=ruby \
        --install-dir "/opt/ruby/gems/$runtime"

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
