#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Run unit tests in Docker
set -e

RUBY_VERSIONS=("2.5")

for ruby_version in "${RUBY_VERSIONS[@]}"
do
    echo "Running tests against ruby${ruby_version}"
    docker build -t datadog-lambda-layer-ruby-test:$ruby_version \
        -f scripts/Dockerfile_test . \
        --quiet \
        --build-arg image=ruby:$ruby_version
done