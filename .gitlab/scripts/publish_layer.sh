#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2024 Datadog, Inc.

# RUBY_VERSION=3.3 REGION=us-east-1

set -e

# Available runtimes: https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
AWS_CLI_RUBY_VERSIONS=(
    "ruby3.2"
    "ruby3.2"
    "ruby3.3"
    "ruby3.3"
    "ruby3.4"
    "ruby3.4"
)
RUBY_VERSIONS=("3.2-amd64" "3.2-arm64" "3.3-amd64" "3.3-arm64" "3.4-amd64" "3.4-arm64")
LAYER_PATHS=(
    ".layers/datadog-lambda_ruby-amd64-3.2.zip"
    ".layers/datadog-lambda_ruby-arm64-3.2.zip"
    ".layers/datadog-lambda_ruby-amd64-3.3.zip"
    ".layers/datadog-lambda_ruby-arm64-3.3.zip"
    ".layers/datadog-lambda_ruby-amd64-3.4.zip"
    ".layers/datadog-lambda_ruby-arm64-3.4.zip"
)
LAYERS=(
    "Datadog-Ruby3-2"
    "Datadog-Ruby3-2-ARM"
    "Datadog-Ruby3-3"
    "Datadog-Ruby3-3-ARM"
    "Datadog-Ruby3-4"
    "Datadog-Ruby3-4-ARM"
)
STAGES=('prod', 'sandbox', 'staging', 'gov-staging', 'gov-prod')

printf "Starting script...\n\n"

publish_layer() {
    region=$1
    layer_name=$2
    compatible_runtimes=$3
    layer_path=$4

    version_nbr=$(aws lambda publish-layer-version --layer-name $layer_name \
        --description "Datadog Lambda Layer for Ruby" \
        --zip-file "fileb://$layer_path" \
        --region $region \
        --compatible-runtimes $compatible_runtimes \
                        | jq -r '.Version')

    permission=$(aws lambda add-layer-version-permission --layer-name $layer_name \
        --version-number $version_nbr \
        --statement-id "release-$version_nbr" \
        --action lambda:GetLayerVersion --principal "*" \
        --region $region)

    echo $version_nbr
}

# Target Ruby version
if [ -z $RUBY_VERSION ]; then
    printf "[Error] RUBY_VERSION version not specified.\n"
    exit 1
fi

printf "Ruby version specified: $RUBY_VERSION\n"
if [[ ! ${RUBY_VERSIONS[@]} =~ $RUBY_VERSION ]]; then
    printf "[Error] Unsupported RUBY_VERSION found.\n"
    exit 1
fi

if [ -z $ARCH ]; then
    printf "[Error] ARCH architecture not specified.\n"
    exit 1
fi

index=0
for i in "${!RUBY_VERSIONS[@]}"; do
    if [[ "${RUBY_VERSIONS[$i]}" = "${RUBY_VERSION}-${ARCH}" ]]; then
       index=$i
    fi
done

REGIONS=$(aws ec2 describe-regions | jq -r '.[] | .[] | .RegionName')

# Target region
if [ -z "$REGION" ]; then
    printf "REGION not specified.\n"
    exit 1
fi

printf "Region specified, region is: $REGION\n"
if [[ ! "$REGIONS" == *"$REGION"* ]]; then
    printf "[Error] Could not find $REGION in AWS available regions: \n${REGIONS[@]}\n"
    exit 1
fi

# Deploy stage
if [ -z "$STAGE" ]; then
    printf "[Error] STAGE not specified.\n"
    printf "Exiting script...\n"
    exit 1
fi

printf "Stage specified: $STAGE\n"
if [[ ! ${STAGES[@]} =~ $STAGE ]]; then
    printf "[Error] Unsupported STAGE found.\n"
    exit 1
fi

layer="${LAYERS[$index]}"
if [ -z "$LAYER_NAME_SUFFIX" ]; then
    echo "No layer name suffix"
else
    layer="${layer}-${LAYER_NAME_SUFFIX}"
fi
echo "layer name: $layer"

if [[ "$STAGE" =~ ^(staging|sandbox|gov-staging)$ ]]; then
    # Deploy latest version
    latest_version=$(aws lambda list-layer-versions --region $REGION --layer-name $layer --query 'LayerVersions[0].Version || `0`')
    VERSION=$(($latest_version + 1))
else
    # Running on prod
    if [ -z "$CI_COMMIT_TAG" ]; then
        printf "[Error] No CI_COMMIT_TAG found.\n"
        printf "Exiting script...\n"
        exit 1
    else
        printf "Tag found in environment: $CI_COMMIT_TAG\n"
    fi

    VERSION=$(echo "${CI_COMMIT_TAG##*v}" | cut -d. -f2)
fi

# Target layer version
if [ -z "$VERSION" ]; then
    printf "[Error] VERSION for layer version not specified.\n"
    printf "Exiting script...\n"
    exit 1
else
    printf "Layer version parsed: $VERSION\n"
fi

printf "[$REGION] Starting publishing layers...\n"
aws_cli_ruby_version_key="${AWS_CLI_RUBY_VERSIONS[$index]}"
layer_path="${LAYER_PATHS[$index]}"

latest_version=$(aws lambda list-layer-versions --region $REGION --layer-name $layer --query 'LayerVersions[0].Version || `0`')
if [ $latest_version -ge $VERSION ]; then
    printf "[$REGION] Layer $layer version $VERSION already exists in region $REGION, skipping...\n"
    exit 0
elif [ $latest_version -lt $((VERSION-1)) ]; then
    printf "[$REGION][WARNING] The latest version of layer $layer in region $REGION is $latest_version, this will publish all the missing versions including $VERSION\n"
fi

while [ $latest_version -lt $VERSION ]; do
    latest_version=$(publish_layer $REGION $layer $aws_cli_ruby_version_key $layer_path)
    printf "[$REGION] Published version $latest_version for layer $layer in region $REGION\n"

    # This shouldn't happen unless someone manually deleted the latest version, say 28, and
    # then tries to republish 28 again. The published version would actually be 29, because
    # Lambda layers are immutable and AWS will skip deleted version and use the next number.
    if [ $latest_version -gt $VERSION ]; then
        printf "[$REGION] Published version $latest_version is greater than the desired version $VERSION!"
        exit 1
    fi
done

printf "[$REGION] Finished publishing layers...\n\n"
