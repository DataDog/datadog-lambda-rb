#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Builds Datadog ruby layers for lambda functions, using Docker
set -e

LAYER_DIR=".layers"
LAYER_FILES_PREFIX="datadog-lambda_ruby"
RUBY_VERSIONS=("3.2" "3.3" "3.4" "4.0")
ARCHITECTURES=("arm64" "amd64")

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

if [ -z "$ARCH" ]; then
    echo "Architecture not specified, running for all architectures."
else
    echo "Architecture is specified: $ARCH"
    if (printf '%s\n' "${ARCHITECTURES[@]}" | grep -xq $ARCH); then
        ARCHITECTURES=($ARCH)
    else
        echo "Unsupported architecture found, valid options are : ${ARCHITECTURES[@]}"
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
    ref=$4

    # Install datadog ruby in a docker container to avoid the mess from switching
    # between different ruby runtimes.
    #
    # NOTE: using the Lambda base image so native extensions (FFI, libddwaf)
    #       compile against the same libffi available at runtime on Lambda.
    temp_dir=$(mktemp -d)
    docker buildx build -t datadog-lambda-ruby-${arch}:$1 . --no-cache \
        --build-arg "image=public.ecr.aws/lambda/ruby:${1}" \
        --build-arg "runtime=${1}.0" \
        --build-arg "git_ref=${ref}" \
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

for ruby_version in "${RUBY_VERSIONS[@]}"
do
    for arch in "${ARCHITECTURES[@]}"
    do
        echo "Building layer for Ruby ${ruby_version} arch=${arch}"
        docker_build_zip ${ruby_version} $LAYER_DIR/${LAYER_FILES_PREFIX}-${arch}-${ruby_version}.zip ${arch} $GIT_REF
    done
done


echo "Done creating layers:"
ls $LAYER_DIR | xargs -I _ echo "$LAYER_DIR/_"
