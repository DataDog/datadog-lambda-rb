#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc

# Usage: VERSION=5 ./scripts/publish_sandbox.sh

set -e

./scripts/build_layers.sh
aws-vault exec sso-serverless-sandbox-account-admin -- ./scripts/sign_layers.sh sandbox
aws-vault exec sso-serverless-sandbox-account-admin -- ./scripts/publish_layers.sh

# Automatically create PR against github.com/DataDog/documentation
# If you'd like to test, please uncomment the below line
# VERSION=$VERSION LAYER=datadog-lambda-rb ./scripts/create_documentation_pr.sh
