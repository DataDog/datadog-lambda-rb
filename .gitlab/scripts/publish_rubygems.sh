#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2024 Datadog, Inc.

set -e

GEM_HOST_API_KEY=$(aws ssm get-parameter \
    --region us-east-1 \
    --name "ci.datadog-lambda-rb.rubygems-api-key" \
    --with-decryption \
    --query "Parameter.Value" \
    --out text)

if [ -z "$CI_COMMIT_TAG" ]; then
    printf "[Error] No CI_COMMIT_TAG found.\n"
    printf "Exiting script...\n"
    exit 1
else
    printf "Tag found in environment: $CI_COMMIT_TAG\n"
fi

VERSION=${CI_COMMIT_TAG#v}

printf "Building gem with version $VERSION\n"
gem build datadog-lambda

printf 'Publishing to RubyGems\n'
GEM_HOST_API_KEY=$GEM_HOST_API_KEY gem push datadog-lambda-$VERSION.gem
