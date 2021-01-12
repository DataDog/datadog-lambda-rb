# Contributing

We love pull requests. Here's a quick guide.

1. Fork, clone and branch off:
    ```bash
    git clone git@github.com:<your-username>/datadog-lambda-rb.git
    git checkout -b <my-branch>
    ```
1. Install the repositories dependencies
    ```bash
    bundle install
    ```
1. Lint and run tests
    ```bash
    rubocop
    ./scripts/run_tests.sh
    ```
1. Build a testing Lambda layer and publish it to your own AWS account.
    ```bash
    # Build layers using docker
    ./scripts/build_layers.sh

    # Publish the a testing layer to your own AWS account, and the ARN will be returned
    # Example: ./scripts/publish_layers.sh us-east-1
    ./scripts/publish_layers.sh <AWS_REGION>
    ```
1. Test your own serverless application using the testing Lambda layer in your own AWS account.
1. Run the integration tests against your own AWS account and Datadog org (or ask a Datadog member to run):
   ```bash
   BUILD_LAYERS=true DD_API_KEY=<your Datadog api key> ./scripts/run_integration_tests.sh
   ```
1. Update integration test snapshots if needed:
   ```bash
   UPDATE_SNAPSHOTS=true DD_API_KEY=<your Datadog api key> ./scripts/run_integration_tests.sh
   ```
1. Push to your fork and [submit a pull request][pr].

[pr]: https://github.com/your-username/datadog-lambda-rb/compare/DataDog:main...main

At this point you're waiting on us. We may suggest some changes or improvements or alternatives.
