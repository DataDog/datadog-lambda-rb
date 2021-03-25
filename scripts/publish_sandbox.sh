#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc

set -e

./scripts/build_layers.sh
aws-vault exec sandbox-account-admin -- ./scripts/sign_layers.sh sandbox
aws-vault exec sandbox-account-admin -- ./scripts/publish_layers.sh
