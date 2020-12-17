#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc

set -e

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ $BRANCH != "main" ]; then
    echo "Not on main, aborting"
    exit 1
fi

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo 'AWS_ACCESS_KEY_ID not set. Are you using aws-vault?'
    exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo 'AWS_SECRET_ACCESS_KEY not set. Are you using aws-vault?'
    exit 1
fi

if [ -z "$AWS_SESSION_TOKEN" ]; then
    echo 'AWS_SESSION_TOKEN not set. Are you using aws-vault?'
    exit 1
fi

gem signin

./scripts/run_tests.sh

echo 'Checking Regions'
./scripts/list_layers.sh

PACKAGE_VERSION=$(gem build datadog-lambda | grep Version | sed -n -e 's/^.*Version: //p')

echo 'Publishing to RubyGems'
gem push "datadog-lambda-${PACKAGE_VERSION}.gem"

echo 'Tagging Release'
git tag "v$PACKAGE_VERSION"
git push origin "refs/tags/v$PACKAGE_VERSION"

echo 'Building layers...'
./scripts/build_layers.sh

echo 'Signing layers...'
./scripts/sign_layers.sh prod

echo 'Publishing layers...'
./scripts/publish_layers.sh
