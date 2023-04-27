ARG image
FROM $image
ARG runtime
# Install dev dependencies
COPY . /var/task/datadog-lambda-ruby
WORKDIR /var/task/datadog-lambda-ruby
RUN yum install -y gcc zip binutils
RUN gem build datadog-lambda
RUN gem install datadog-lambda --install-dir "/opt/ruby/gems/${runtime}"
# v0.48 has a bug : https://github.com/DataDog/dd-trace-rb/issues/1475
RUN gem install ddtrace -v 1.11.0 --install-dir "/opt/ruby/gems/${runtime}"
# Cache files zipped gem files, that aren't used by during runtime, only during 
# installation, so they are safe to delete
RUN rm -rf "/opt/ruby/gems/${runtime}/cache"
RUN cd /opt
