#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Builds Datadog ruby layers for lambda functions, using Docker
set -e

LAYER_DIR=".layers"
LAYER_FILES_PREFIX="datadog-lambda_ruby"
RUBY_VERSIONS=("2.5")

function make_path_absolute {
    echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"
}

function docker_build_zip {
    # Args: [ruby version] [zip destination]

    destination=$(make_path_absolute $2)

    # Install datadog ruby in a docker container to avoid the mess from switching
    # between different ruby runtimes.
    temp_dir=$(mktemp -d)
    docker build -t datadog-lambda-layer-ruby:$1 . --no-cache \
	-f Dockerfile.build \
        --build-arg "image=lambci/lambda:build-ruby${1}" --build-arg "runtime=${1}.0"

    # Run the image by runtime tag, tar its generatd `ruby` directory to sdout,
    # then extract it to a temp directory.
    docker run --rm datadog-lambda-layer-ruby:$1 tar cf - /opt/ruby | tar -xf - -C $temp_dir

    # Zip to destination, and keep directory structure as based in $temp_dir
    (cd $temp_dir/opt/ && zip -q -r $destination ./)

    rm -rf $temp_dir
    echo "Done creating archive $destination"
}

rm -rf $LAYER_DIR
mkdir $LAYER_DIR

for ruby_version in "${RUBY_VERSIONS[@]}"
do
    echo "Building layer for ruby${ruby_version}"
    docker_build_zip ${ruby_version} $LAYER_DIR/${LAYER_FILES_PREFIX}${ruby_version}.zip
done


echo "Done creating layers:"
ls $LAYER_DIR | xargs -I _ echo "$LAYER_DIR/_"
