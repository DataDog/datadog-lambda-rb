# datadog-lambda-rb

[![CircleCI](https://img.shields.io/circleci/build/github/DataDog/datadog-lambda-rb)](https://circleci.com/gh/DataDog/workflows/datadog-lambda-rb)
[![RubyGem](https://img.shields.io/gem/v/datadog-lambda)](https://rubygems.org/gems/datadog-lambda)
[![Slack](https://img.shields.io/badge/slack-%23serverless-blueviolet?logo=slack)](https://datadoghq.slack.com/channels/serverless/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/DataDog/datadog-lambda-rb/blob/master/LICENSE)

Datadog Lambda Library for Ruby (2.5 and 2.7) enables enhanced Lambda metrics, distributed tracing, and custom metric submission from AWS Lambda functions.

## Installation

Check out our [installation instructions for Ruby](https://docs.datadoghq.com/serverless/installation/ruby/).

## Environment Variables

### DD_LOG_LEVEL

Set to `debug` enable debug los from the Datadog Lambda Library. Defaults to `info`.

### DD_ENHANCED_METRICS

Generate enhanced Datadog Lambda integration metrics, such as, `aws.lambda.enhanced.invocations` and `aws.lambda.enhanced.errors`. Defaults to `true`.

### DD_MERGE_DATADOG_XRAY_TRACES

Set to `true` to merge the X-Ray trace and the Datadog trace, when using both the X-Ray and Datadog tracing. Defaults to `false`.

## Custom Metrics

Check out the instructions for [submitting custom metrics from AWS Lambda functions](https://docs.datadoghq.com/integrations/amazon_lambda/?tab=ruby#custom-metrics).

## Tracing

Check out the instructions for [collecting traces from AWS Lambda functions](https://docs.datadoghq.com/integrations/amazon_lambda/?tab=ruby#trace-collection), and the [official documentation for Datadog trace client](https://github.com/DataDog/dd-trace-rb/blob/master/docs/GettingStarted.md).

## Opening Issues

If you encounter a bug with this package, we want to hear about it. Before opening a new issue, search the existing issues to avoid duplicates.

When opening an issue, include the Datadog Lambda Layer version, Ruby version, and stack trace if available. In addition, include the steps to reproduce when appropriate.

You can also open an issue for a feature request.

## Contributing

If you find an issue with this package and have a fix, please feel free to open a pull request following the [procedures](https://github.com/DataDog/dd-lambda-layer-rb/blob/master/CONTRIBUTING.md).

## License

Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.

This product includes software developed at Datadog (https://www.datadoghq.com/). Copyright 2019 Datadog, Inc.
