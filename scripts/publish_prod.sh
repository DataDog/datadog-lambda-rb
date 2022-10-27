#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc
#
# Use with `./publish_prod.sh <DESIRED_NEW_VERSION>

set -e

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ $BRANCH != "main" ]; then
    echo "Not on main, aborting"
    exit 1
else
    echo "Updating main"
    git pull origin main
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Detected uncommitted changes, aborting"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Must specify a desired version number"
    exit 1
elif [[ ! $1 =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "Must use a semantic version, e.g., 3.1.4"
    exit 1
else
    NEW_VERSION=$1
fi

echo "Running tests"
./scripts/run_tests.sh

echo "Ensure you have access to gem account"
gem signin

echo "Ensure you have access to the AWS GovCloud account"
saml2aws login -a govcloud-us1-fed-human-engineering
AWS_PROFILE=govcloud-us1-fed-human-engineering aws sts get-caller-identity

echo "Ensure you have access to the commercial AWS GovCloud account"
aws-vault exec prod-engineering -- aws sts get-caller-identity

CURRENT_VERSION=$(gem build datadog-lambda | grep Version | sed -n -e 's/^.*Version: //p')
MAJOR_VERSION=$(echo $NEW_VERSION | cut -d '.' -f 1)
LAYER_VERSION=$(echo $NEW_VERSION | cut -d '.' -f 2)  # MINOR_VERSION === LAYER_VERSION
PATCH_VERSION=$(echo $NEW_VERSION | cut -d '.' -f 3)

read -p "Ready to update the library version from $CURRENT_VERSION to $NEW_VERSION and publish layer version $LAYER_VERSION (y/n)?" CONT
if [ "$CONT" != "y" ]; then
    echo "Exiting"
    exit 1
fi

echo
echo "Updating version in ./lib/datadog/lambda/version.rb"
echo
sed -i "" -E "s/(MAJOR = )(0|[1-9][0-9]*)/\1$MAJOR_VERSION/" ./lib/datadog/lambda/version.rb
sed -i "" -E "s/(MINOR = )(0|[1-9][0-9]*)/\1$LAYER_VERSION/" ./lib/datadog/lambda/version.rb
sed -i "" -E "s/(PATCH = )(0|[1-9][0-9]*)/\1$PATCH_VERSION/" ./lib/datadog/lambda/version.rb

echo
echo 'Building layers...'
./scripts/build_layers.sh

echo
echo "Signing layers for commercial AWS regions"
aws-vault exec prod-engineering -- ./scripts/sign_layers.sh prod

echo
echo "Publishing layers to commercial AWS regions"
VERSION=$LAYER_VERSION aws-vault exec prod-engineering --no-session -- ./scripts/publish_layers.sh

echo "Publishing layers to GovCloud AWS regions"
saml2aws login -a govcloud-us1-fed-human-engineering
VERSION=$LAYER_VERSION AWS_PROFILE=govcloud-us1-fed-human-engineering ./scripts/publish_layers.sh

read -p "Ready to publish gem $NEW_VERSION (y/n)?" CONT
if [ "$CONT" != "y" ]; then
    echo "Exiting"
    exit 1
fi

echo 'Publishing to RubyGems'
gem push "datadog-lambda-${NEW_VERSION}.gem"

echo
echo 'Publishing updates to github'
git commit lib/datadog/lambda/version.rb -m "Bump version to ${NEW_VERSION}"
git push origin main
git tag "v$NEW_VERSION"
git push origin "refs/tags/v$NEW_VERSION"

echo
echo "Now create a new release with the tag v${NEW_VERSION} created"
echo "https://github.com/DataDog/datadog-lambda-rb/releases/new?tag=v$NEW_VERSION&title=v$NEW_VERSION"

# Open a PR to the documentation repo to automatically bump layer version
VERSION=$LAYER_VERSION LAYER=datadog-lambda-rb ./scripts/create_documentation_pr.sh
