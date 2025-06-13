#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Compares layer size to threshold, and fails if below that threshold

# Previous: 5 mb size limit
# Current state: limits are way too high, a change to
# reduce this is needed in the future.
MAX_LAYER_COMPRESSED_SIZE_KB=$(expr 28 \* 1024) 
MAX_LAYER_UNCOMPRESSED_SIZE_KB=$(expr 100 \* 1024) 


LAYER_FILES_PREFIX="datadog-lambda_ruby"
LAYER_DIR=".layers"
RUBY_VERSIONS=("3.2" "3.3" "3.4")
ARCHITECTURES=("amd64" "arm64")

if [ -z "$ARCH" ]; then
    echo "Architecture not specified, running for all architectures."
else
    echo "ARCH is specified: $ARCHITECTURE"
    if (printf '%s\n' "${ARCHITECTURES[@]}" | grep -xq $ARCH); then
        ARCHITECTURES=($ARCH)
    else
        echo "Unsupported architecture found, valid options are : ${ARCHITECTURES[@]}"
        exit 1
    fi
fi

if [ -z "$RUBY_VERSION" ]; then
    echo "Ruby version not specified, running for all ruby versions."
else
    echo "RUBY_VERSION is specified: $RUBY_VERSION"
    if (printf '%s\n' "${RUBY_VERSIONS[@]}" | grep -xq $RUBY_VERSION); then
        RUBY_VERSIONS=($RUBY_VERSION)
    else
        echo "Unsupported version found, valid options are : ${RUBY_VERSIONS[@]}"
        exit 1
    fi
fi

for version in "${RUBY_VERSIONS[@]}"
do
    for arch in "${ARCHITECTURES[@]}"
    do
        FILE=$LAYER_DIR/${LAYER_FILES_PREFIX}-${arch}-${version}.zip
        FILE_SIZE=$(stat --printf="%s" $FILE)
        FILE_SIZE_KB="$(( ${FILE_SIZE%% *} / 1024))"
        echo "Layer file ${FILE} has zipped size ${FILE_SIZE_KB} kb"
        if [ "$FILE_SIZE_KB" -gt "$MAX_LAYER_COMPRESSED_SIZE_KB" ]; then
            echo "Zipped size exceeded limit $MAX_LAYER_COMPRESSED_SIZE_KB kb"
            exit 1
        fi
        mkdir tmp
        unzip -q $FILE -d tmp
        UNZIPPED_FILE_SIZE=$(du -shb tmp/ | cut -f1)
        UNZIPPED_FILE_SIZE_KB="$(( ${UNZIPPED_FILE_SIZE%% *} / 1024))"
        rm -rf tmp
        echo "Layer file ${FILE} has unzipped size ${UNZIPPED_FILE_SIZE_KB} kb"
        if [ "$UNZIPPED_FILE_SIZE_KB" -gt "$MAX_LAYER_UNCOMPRESSED_SIZE_KB" ]; then
            echo "Unzipped size exceeded limit $MAX_LAYER_UNCOMPRESSED_SIZE_KB kb"
            exit 1
        fi
    done
done