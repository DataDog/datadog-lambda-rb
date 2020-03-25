# datadog-lambda-layer-rb

[![CircleCI](https://img.shields.io/circleci/build/github/DataDog/datadog-lambda-layer-rb)](https://circleci.com/gh/DataDog/workflows/datadog-lambda-layer-rb)
[![RubyGem](https://img.shields.io/gem/v/datadog-lambda)](https://rubygems.org/gems/datadog-lambda)
[![Slack](https://img.shields.io/badge/slack-%23serverless-blueviolet?logo=slack)](https://datadoghq.slack.com/channels/serverless/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/DataDog/datadog-lambda-layer-rb/blob/master/LICENSE)

Datadog's Lambda ruby client library enables distributed tracing between serverful and serverless environments, as well as letting you send custom metrics to the Datadog API.

## Installation

This library is provided both as an AWS Lambda Layer, and a gem. If you want to get off the ground quickly and don't need to bundle your dependencies locally, the Lambda Layer method is the recommended approach.

### Gem method

You can install the package library locally by adding the following line to your Gemfile

```gemfile
gem 'datadog-lambda'
```

### Lambda Layer Method

Datadog Lambda Layer can be added to a Lambda function via AWS Lambda console, [AWS CLI](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html#configuration-layers-using) or [Serverless Framework](https://serverless.com/framework/docs/providers/aws/guide/layers/#using-your-layers) using the following ARN.

```
arn:aws:lambda:<AWS_REGION>:464622532012:layer:Datadog-Ruby2-5:<VERSION>
# OR
arn:aws:lambda:<AWS_REGION>:464622532012:layer:Datadog-Ruby2-7:<VERSION>
```

Replace `<AWS_REGION>` with the region where your Lambda function lives, and `<VERSION>` with the desired (or the latest) version that can be found from [CHANGELOG](https://github.com/DataDog/datadog-lambda-layer-rb/releases).

### The Serverless Framework

If your Lambda function is deployed using the Serverless Framework, refer to this sample `serverless.yml`. Make sure to replace `<VERSION>` with the [latest release](https://github.com/DataDog/datadog-lambda-layer-rb/releases/latest) of the layer.

```yaml
provider:
  name: aws
  runtime: ruby2.5
  tracing:
    lambda: true
    apiGateway: true

functions:
  hello:
    handler: handler.hello
    events:
      - http:
          path: hello
          method: get
    layers:
      - arn:aws:lambda:us-east-1:464622532012:layer:Datadog-Ruby2-5:<VERSION>
```

## Environment Variables

You can set the following environment variables via the AWS CLI or Serverless Framework

### DD_LOG_LEVEL

How much logging datadog-lambda-layer-rb should do. Set this to "debug" for extensive logs.

### DD_ENHANCED_METRICS

If you set the value of this variable to "true" then the Lambda layer will increment a Lambda integration metric called `aws.lambda.enhanced.invocations` with each invocation and `aws.lambda.enhanced.errors` if the invocation results in an error. These metrics are tagged with the function name, region, account, runtime, memorysize, and `cold_start:true|false`.

## Usage

Datadog needs to be able to read headers from the incoming Lambda event.

```ruby
require 'datadog/lambda'

def handler(event:, context:)
    Datadog::Lambda.wrap(event, context) do
        # Implement your logic here
        return { statusCode: 200, body: 'Hello World' }
    end
end
```

## Custom Metrics

Custom metrics can be submitted using the `metric` function. The metrics are submitted as [distribution metrics](https://docs.datadoghq.com/graphing/metrics/distributions/).

**IMPORTANT NOTE:** If you have already been submitting the same custom metric as non-distribution metric (e.g., gauge, count, or histogram) without using the Datadog Lambda Layer, you MUST pick a new metric name to use for `sendDistributionMetric`. Otherwise that existing metric will be converted to a distribution metric and the historical data prior to the conversion will be no longer queryable.

```ruby
require 'datadog/lambda'

Datadog::Lambda.metric(
  'coffee_house.order_value',
  12.45,
  "product":"latte",
  "order":"online"
)
```

### VPC

If your Lambda function is associated with a VPC, you need to ensure it has access to the [public internet](https://aws.amazon.com/premiumsupport/knowledge-center/internet-access-lambda-function/).

## Distributed Tracing

[Distributed tracing](https://docs.datadoghq.com/tracing/) allows you to propagate a trace context from a service running on a host to a service running on AWS Lambda, and vice versa, so you can see performance end-to-end. Linking is implemented by injecting Datadog trace context into the HTTP request headers.

Distributed tracing headers are language agnostic, e.g., a trace can be propagated between a Java service running on a host to a Lambda function written in Ruby.

Because the trace context is propagated through HTTP request headers, the Lambda function needs to be triggered by AWS API Gateway or AWS Application Load Balancer.

To enable this feature wrap your handler functions using the `datadog` function.

### Sampling

The traces for your Lambda function are converted by Datadog from AWS X-Ray traces. X-Ray needs to sample the traces that the Datadog tracing agent decides to sample, in order to collect as many complete traces as possible. You can create X-Ray sampling rules to ensure requests with header `x-datadog-sampling-priority:1` or `x-datadog-sampling-priority:2` via API Gateway always get sampled by X-Ray.

These rules can be created using the following AWS CLI command.

```bash
aws xray create-sampling-rule --cli-input-json file://datadog-sampling-priority-1.json
aws xray create-sampling-rule --cli-input-json file://datadog-sampling-priority-2.json
```

The file content for `datadog-sampling-priority-1.json`:

```json
{
  "SamplingRule": {
    "RuleName": "Datadog-Sampling-Priority-1",
    "ResourceARN": "*",
    "Priority": 9998,
    "FixedRate": 1,
    "ReservoirSize": 100,
    "ServiceName": "*",
    "ServiceType": "AWS::APIGateway::Stage",
    "Host": "*",
    "HTTPMethod": "*",
    "URLPath": "*",
    "Version": 1,
    "Attributes": {
      "x-datadog-sampling-priority": "1"
    }
  }
}
```

The file content for `datadog-sampling-priority-2.json`:

```json
{
  "SamplingRule": {
    "RuleName": "Datadog-Sampling-Priority-2",
    "ResourceARN": "*",
    "Priority": 9999,
    "FixedRate": 1,
    "ReservoirSize": 100,
    "ServiceName": "*",
    "ServiceType": "AWS::APIGateway::Stage",
    "Host": "*",
    "HTTPMethod": "*",
    "URLPath": "*",
    "Version": 1,
    "Attributes": {
      "x-datadog-sampling-priority": "2"
    }
  }
}
```

## Datadog Tracer (**Experimental**)

You can now trace Lambda functions using Datadog APM's tracing libraries ([dd-trace-rb](https://github.com/DataDog/dd-trace-rb)).

1. If you are using the Lambda layer, upgrade it to at least version 6.
1. If you are using the npm package `datadog-lambda-rb`, upgrade it to at least version `v0.6.0`. You also need to install the latest version of the datadog tracer: `gem install ddtrace`. Keep in mind that ddtrace uses native extensions, which must be compiled for Amazon Linux before being packaged and uploaded to lambda. For this reason we recommend using the lambda layer.
1. Install (or update to) the latest version of [Datadog forwarder Lambda function](https://docs.datadoghq.com/integrations/amazon_web_services/?tab=allpermissions#set-up-the-datadog-lambda-function). Ensure the trace forwarding layer is attached to the forwarder, e.g., ARN for Python 3.7 `arn:aws:lambda:<AWS_REGION>:464622532012:layer:Datadog-Trace-Forwarder-Python37:4`.
1. To initialise the tracer, call `Datadog::Lambda.configure_apm`. It takes the same arguments as [Datadog.configure](https://github.com/DataDog/dd-trace-rb/blob/master/docs/GettingStarted.md#quickstart-for-ruby-applications), except with defaults that enable lambda tracing

```ruby
require 'ddtrace'
require 'datadog/lambda'

Datadog::Lambda.configure_apm do |c|
# Enable instrumentation here
end

def handler(event:, context:)
  Datadog::Lambda::wrap(event, context) do
    # Your function code here
    some_operation()
  end
end

# Instrument the rest of your code using ddtrace

def some_operation()
    Datadog.tracer.trace('some_operation') do |span|
        # Do something here
    end
end
```

1. You can also use `ddtrace` and the X-Ray tracer together and merge the traces into one, by setting the environment variable `DD_MERGE_DATADOG_XRAY_TRACES` to true

## Non-proxy integration

If your Lambda function is triggered by API Gateway via the non-proxy integration, then you have to set up a mapping template, which passes the Datadog trace context from the incoming HTTP request headers to the Lambda function via the event object.

If your Lambda function is deployed by the Serverless Framework, such a mapping template gets created by default.

## Opening Issues

If you encounter a bug with this package, we want to hear about it. Before opening a new issue, search the existing issues to avoid duplicates.

When opening an issue, include the Datadog Lambda Layer version, Ruby version, and stack trace if available. In addition, include the steps to reproduce when appropriate.

You can also open an issue for a feature request.

## Contributing

If you find an issue with this package and have a fix, please feel free to open a pull request following the [procedures](https://github.com/DataDog/dd-lambda-layer-rb/blob/master/CONTRIBUTING.md).

## License

Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.

This product includes software developed at Datadog (https://www.datadoghq.com/). Copyright 2019 Datadog, Inc.
