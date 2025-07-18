#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Publish the datadog ruby lambda layer across regions, using the AWS CLI
# Usage: VERSION=5 REGIONS=us-east-1 LAYERS=Datadog-Ruby2-7 publish_layers.sh
# VERSION is required.
set -e

RUBY_VERSIONS_FOR_AWS_CLI=("ruby3.2" "ruby3.2" "ruby3.3" "ruby3.3" "ruby3.4" "ruby3.4")
LAYER_PATHS=(".layers/datadog-lambda_ruby-amd64-3.2.zip" ".layers/datadog-lambda_ruby-arm64-3.2.zip" ".layers/datadog-lambda_ruby-amd64-3.3.zip" ".layers/datadog-lambda_ruby-arm64-3.3.zip" ".layers/datadog-lambda_ruby-amd64-3.4.zip" ".layers/datadog-lambda_ruby-arm64-3.4.zip")
AVAILABLE_LAYERS=("Datadog-Ruby3-2" "Datadog-Ruby3-2-ARM" "Datadog-Ruby3-3" "Datadog-Ruby3-3-ARM" "Datadog-Ruby3-4" "Datadog-Ruby3-4-ARM")
AVAILABLE_REGIONS=$(aws ec2 describe-regions | jq -r '.[] | .[] | .RegionName')


# Check that the layer files exist
for layer_file in "${LAYER_PATHS[@]}"
do
    if [ ! -f $layer_file  ]; then
        echo "Could not find $layer_file."
        exit 1
    fi
done

# Determine the target regions
if [ -z "$REGIONS" ]; then
    echo "Region not specified, running for all available regions."
    REGIONS=$AVAILABLE_REGIONS
else
    echo "Region specified: $REGIONS"
    if [[ ! "$AVAILABLE_REGIONS" == *"$REGIONS"* ]]; then
        echo "Could not find $REGIONS in available regions: $AVAILABLE_REGIONS"
        echo ""
        echo "EXITING SCRIPT."
        exit 1
    fi
fi

# Determine the target layers
if [ -z "$LAYERS" ]; then
    echo "Layer not specified, running for all layers."
    LAYERS=("${AVAILABLE_LAYERS[@]}")
else
    echo "Layer specified: $LAYERS"
    if [[ ! " ${AVAILABLE_LAYERS[@]} " =~ " ${LAYERS} " ]]; then
        echo "Could not find $LAYERS in available layers: ${AVAILABLE_LAYERS[@]}"
        echo ""
        echo "EXITING SCRIPT."
        exit 1
    fi
fi

# Determine the target layer version
if [ -z "$VERSION" ]; then
    echo "Layer version not specified"
    echo ""
    echo "EXITING SCRIPT."
    exit 1
else
    echo "Layer version specified: $VERSION"
fi

read -p "Ready to publish version $VERSION of layers ${LAYERS[*]} to regions ${REGIONS[*]} (y/n)?" CONT
if [ "$CONT" != "y" ]; then
    echo "Exiting"
    exit 1
fi

index_of_layer() {
    layer_name=$1
    for i in "${!AVAILABLE_LAYERS[@]}"; do
        if [[ "${AVAILABLE_LAYERS[$i]}" = "${layer_name}" ]]; then
            echo "${i}";
        fi
    done
}

publish_layer() {
    region=$1
    layer_name=$2
    aws_version_key=$3
    layer_path=$4

    version_nbr=$(aws lambda publish-layer-version --layer-name $layer_name \
        --description "Datadog Lambda Layer for Ruby" \
        --zip-file "fileb://$layer_path" \
        --region $region \
        --compatible-runtimes $aws_version_key \
                        | jq -r '.Version')

    permission=$(aws lambda add-layer-version-permission --layer-name $layer_name \
        --version-number $version_nbr \
        --statement-id "release-$version_nbr" \
        --action lambda:GetLayerVersion --principal "*" \
        --region $region)

    echo $version_nbr
}

for region in $REGIONS
do
    echo "Starting publishing layer for region $region..."

    for layer_name in "${LAYERS[@]}"; do
        latest_version=$(aws lambda list-layer-versions --region $region --layer-name $layer_name --query 'LayerVersions[0].Version || `0`')
        if [ $latest_version -ge $VERSION ]; then
            echo "Layer $layer_name version $VERSION already exists in region $region, skipping..."
            continue
        elif [ $latest_version -lt $((VERSION-1)) ]; then
            read -p "WARNING: The latest version of layer $layer_name in region $region is $latest_version, publish all the missing versions including $VERSION or EXIT the script (y/n)?" CONT
            if [ "$CONT" != "y" ]; then
                echo "Exiting"
                exit 1
            fi
        fi

        index=$(index_of_layer $layer_name)
        aws_version_key="${RUBY_VERSIONS_FOR_AWS_CLI[$index]}"
        layer_path="${LAYER_PATHS[$index]}"

        while [ $latest_version -lt $VERSION ]; do
            latest_version=$(publish_layer $region $layer_name $aws_version_key $layer_path)
            echo "Published version $latest_version for layer $layer_name in region $region"

            # This shouldn't happen unless someone manually deleted the latest version, say 28, and
            # then tries to republish 28 again. The published version would actually be 29, because
            # Lambda layers are immutable and AWS will skip deleted version and use the next number. 
            if [ $latest_version -gt $VERSION ]; then
                echo "ERROR: Published version $latest_version is greater than the desired version $VERSION!"
                echo "Exiting"
                exit 1
            fi
        done
    done
done

echo "Done !"
