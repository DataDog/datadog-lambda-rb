#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Builds Datadog ruby layers for lambda functions, using Docker
set -e

LAYER_DIR=".layers"
LAYER_FILES_PREFIX="datadog-lambda_ruby"
RUBY_VERSIONS=("3.2" "3.3")

if [ -z "$RUBY_VERSION" ]; then
    echo "Ruby version not specified, running for all ruby versions."
else
    echo "Ruby version is specified: $RUBY_VERSION"
    if (printf '%s\n' "${RUBY_VERSIONS[@]}" | grep -xq $RUBY_VERSION); then
        RUBY_VERSIONS=($RUBY_VERSION)
    else
        echo "Unsupported version found, valid options are : ${RUBY_VERSIONS[@]}"
        exit 1
    fi
fi

function make_path_absolute {
    echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"
}

function docker_build_zip {
    # Args: [ruby version] [zip destination] [architecture]

    destination=$(make_path_absolute $2)
    arch=$3

    # Install datadog ruby in a docker container to avoid the mess from switching
    # between different ruby runtimes.
    temp_dir=$(mktemp -d)
    docker buildx build -t datadog-lambda-ruby-${arch}:$1 . --no-cache \
        --build-arg "image=ruby:${1}" \
        --build-arg "runtime=${1}.0" \
        --platform linux/${arch} \
        --load

    # Run the image by runtime tag and copy the output /opt/ruby to the temp dir/opt/ruby
    dockerId=$(docker create datadog-lambda-ruby-${arch}:$1)
    mkdir $temp_dir/opt/
    docker cp $dockerId:/opt/ruby $temp_dir/opt/ruby

    # Zip to destination, and keep directory structure as based in $temp_dir
    (cd $temp_dir/opt/ && zip -q -r $destination ./)

    rm -rf $temp_dir
    echo "Done creating archive $destination"
}

rm -rf $LAYER_DIR
mkdir $LAYER_DIR

for ruby_version in "${RUBY_VERSIONS[@]}"
do
    echo "Building layer for Ruby ${ruby_version} arch=arm64"
    docker_build_zip ${ruby_version} $LAYER_DIR/${LAYER_FILES_PREFIX}-arm64-${ruby_version}.zip arm64

    echo "Building layer for Ruby ${ruby_version} arch=amd64"
    docker_build_zip ${ruby_version} $LAYER_DIR/${LAYER_FILES_PREFIX}-amd64-${ruby_version}.zip amd64
done


echo "Done creating layers:"
ls $LAYER_DIR | xargs -I _ echo "$LAYER_DIR/_"
