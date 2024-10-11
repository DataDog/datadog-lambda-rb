#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2024 Datadog, Inc.

set -e

LAYER_DIR=".layers"
LAYER_FILES_PREFIX="datadog-lambda_ruby"
AVAILABLE_RUBY_VERSIONS=("3.2" "3.3")

if [ -z "$ARCHITECTURE" ]; then
    echo "[ERROR]: ARCHITECTURE not specified"
    exit 1
fi

# Determine which Ruby version to build layer for
if [ -z "$RUBY_VERSION" ]; then
    echo "[ERROR]: RUBY_VERSION not specified"
    exit 1
else
    echo "Ruby version specified: $RUBY_VERSION"
    if [[ ! " ${AVAILABLE_RUBY_VERSIONS[@]} " =~ " ${RUBY_VERSION} " ]]; then
        echo "Ruby version $RUBY_VERSION is not a valid option. Choose from: ${AVAILABLE_RUBY_VERSIONS[@]}"
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
        --progress=plain \
        -o $temp_dir

    # Zip to destination, and keep directory structure as based in $temp_dir
    (cd $temp_dir && zip -q -r $destination ./)

    rm -rf $temp_dir
    echo "Done creating archive $destination"
}

rm -rf $LAYER_DIR
mkdir $LAYER_DIR

echo "Building layer for Ruby $RUBY_VERSION with architecture $ARCHITECTURE"
docker_build_zip $RUBY_VERSION $LAYER_DIR/${LAYER_FILES_PREFIX}-${ARCHITECTURE}-${RUBY_VERSION}.zip $ARCHITECTURE

echo "Done creating layers:"
ls $LAYER_DIR | xargs -I _ echo "$LAYER_DIR/_"
