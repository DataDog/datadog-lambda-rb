#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Publish the datadog ruby lambda layer across regions, using the AWS CLI
# Usage: publish_layer.sh [region]
# Specifying the region arg will publish the layer for the single specified region

set -e

LAYER_NAME=Datadog-Ruby2-5
PROD_ACCOUNT=464622532012
AVAILABLE_REGIONS=(us-east-2 us-east-1 us-west-1 us-west-2 ap-south-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 ap-northeast-1 ca-central-1 eu-north-1 eu-central-1 eu-west-1 eu-west-2 eu-west-3 sa-east-1)

list_layers () {
	outfile=$1
	for region in "${AVAILABLE_REGIONS[@]}"
	do
		thisArn=arn:aws:lambda:$region:$PROD_ACCOUNT:layer:$LAYER_NAME
		last_layer_arn=$(aws lambda list-layer-versions --layer-name $thisArn --region $region | jq -r ".LayerVersions | .[0] |  .Version")
		if [ -z $last_layer_arn ]; then
			>&2 echo "Unable to list layers for " $thisArn
			exit 1
		fi
		echo $last_layer_arn >> $outfile
	done
}

NEW_PACKAGE_VERSION=$(gem build datadog-lambda | grep Version | sed -n -e 's/^.*Version: //p' | perl -n -e'/\.(\d)\./ && print $1')

LAYERLIST=$(mktemp)
list_layers $LAYERLIST

DISCRETE_LAYERS=$(cat $LAYERLIST |  sort | uniq | wc -l)
if [ $DISCRETE_LAYERS != 1 ]; then
       >&2 echo "Unexpected number of discrete deployed layer versions found: " $DISCRETE_LAYERS
       exit 1
fi

LATEST_LAYER_NUMBER=$(cat $LAYERLIST | head -n 1)

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
