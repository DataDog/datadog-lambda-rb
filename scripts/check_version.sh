#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Publish the datadog ruby lambda layer across regions, using the AWS CLI
# Usage: publish_layer.sh [region]
# Specifying the region arg will publish the layer for the single specified region

set -e

NEW_PACKAGE_VERSION=$(gem build datadog-lambda | grep Version | sed -n -e 's/^.*Version: //p' | perl -n -e'/\.(\d)\./ && print $1')

LAYERLIST=$(mktemp)
./scripts/list_layers.sh | grep arn > $LAYERLIST

DISCRETE_LAYERS=$(cat $LAYERLIST | cut -d ':' -f 8 | sort | uniq | wc -l)

if [ $DISCRETE_LAYERS != 1 ]; then
	>&2 echo "Unexpected number of discrete deployed layer versions found: " $DISCRETE_LAYERS
	exit 1
fi

LATEST_LAYER_NUMBER=$(cat $LAYERLIST | cut -d ':' -f 8 | head -n 1)

LATEST_GEM_VERSION=$(gem list datadog-lambda --remote | perl -n -e'/\.(\d)\./ && print $1')

>&2 echo "New package version: " $NEW_PACKAGE_VERSION
>&2 echo "Latest published layer: " $LATEST_LAYER_NUMBER
>&2 echo "Latest published gem: " $LATEST_GEM_VERSION

((NEW_PACKAGE_VERSION=$NEW_PACKAGE_VERSION-1))

#NEW_PACKAGE_VERSION should be one greater than LATEST_LAYER_NUMBER
if [ $NEW_PACKAGE_VERSION != $LATEST_LAYER_NUMBER ]; then
	>&2 echo "Expected new package minor version to be one grater than the current latest layer number"
	exit 1
fi

#NEW_PACKAGE_VERSION should be one greater than LATEST_GEM VERSION
if [ $NEW_PACKAGE_VERSION != $LATEST_GEM_VERSION ]; then
	>&2 echo "Expected the new package minor version to be one greater than the currently deployed minor version"
	exit 1
fi
