variables:
  CI_DOCKER_TARGET_IMAGE: registry.ddbuild.io/ci/datadog-lambda-rb
  CI_DOCKER_TARGET_VERSION: latest

stages:
 - build
 - test
 - sign
 - publish

default:
  retry:
    max: 1
    when:
      # Retry when the runner fails to start
      - runner_system_failure

{{ range $runtime := (ds "runtimes").runtimes }}

build layer ({{ $runtime.name }}, {{ $runtime.arch }}):
  stage: build
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  artifacts:
    expire_in: 1 hr # Unsigned zips expire in 1 hour
    paths:
      - .layers/datadog-lambda_ruby-{{ $runtime.arch }}-{{ $runtime.ruby_version }}.zip
  script:
    - RUBY_VERSION={{ $runtime.ruby_version }} ARCH={{ $runtime.arch }} .gitlab/scripts/build_layer.sh

check layer size ({{ $runtime.name }}, {{ $runtime.arch }}):
  stage: test
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  needs: 
    - build layer ({{ $runtime.name }}, {{ $runtime.arch }})
  dependencies:
    - build layer ({{ $runtime.name }}, {{ $runtime.arch }})
  script: 
    - RUBY_VERSION={{ $runtime.ruby_version }} ARCH={{ $runtime.arch }} ./scripts/check_layer_size.sh

lint ({{$runtime.name}}, {{ $runtime.arch }}):
  stage: test
  tags: ["arch:amd64"]
  image: registry.ddbuild.io/images/mirror/ruby:{{ $runtime.image }}
  needs: []
  cache: &{{ $runtime.name }}-{{ $runtime.arch }}-cache
  script: 
    - bundle install
    - bundle exec rubocop

unit test ({{ $runtime.name }}, {{ $runtime.arch }}):
  stage: test
  tags: ["arch:amd64"]
  image: registry.ddbuild.io/images/mirror/ruby:{{ $runtime.image }}
  needs: []
  cache: &{{ $runtime.name }}-{{ $runtime.arch }}-cache
  script: 
    - bundle install
    - bundle exec rake test

integration test ({{ $runtime.name }}, {{ $runtime.arch }}):
  stage: test
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  needs: 
    - build layer ({{ $runtime.name }}, {{ $runtime.arch }})
  dependencies:
    - build layer ({{ $runtime.name }}, {{ $runtime.arch }})
  cache: &{{ $runtime.name }}-{{ $runtime.arch }}-cache
  before_script:
    - EXTERNAL_ID_NAME=integration-test-externalid ROLE_TO_ASSUME=sandbox-integration-test-deployer AWS_ACCOUNT=425362996713 source .gitlab/scripts/get_secrets.sh
    - cd integration_tests && yarn install && cd ..
  script:
    - RUNTIME_PARAM={{ $runtime.ruby_version }} ARCH={{ $runtime.arch }} ./scripts/run_integration_tests.sh

{{ range $environment := (ds "environments").environments }}

{{ if or (eq $environment.name "prod") }}
sign layer ({{ $runtime.name }}, {{ $runtime.arch }}):
  stage: sign
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v.*/'
      when: manual
  needs:
    - build layer ({{ $runtime.name }}, {{ $runtime.arch }})
    - check layer size ({{ $runtime.name }}, {{ $runtime.arch }})
    - lint ({{$runtime.name}}, {{ $runtime.arch }})
    - unit test ({{ $runtime.name }}, {{ $runtime.arch }})
    - integration test ({{ $runtime.name }}, {{ $runtime.arch }})
  dependencies:
    - build layer ({{ $runtime.name }}, {{ $runtime.arch }})
  artifacts: # Re specify artifacts so the modified signed file is passed
    expire_in: 1 day # Signed layers should expire after 1 day
    paths:
      - .layers/datadog_lambda_ruby-{{ $runtime.arch }}-{{ $runtime.ruby_version }}.zip
  before_script:
    - EXTERNAL_ID_NAME={{ $environment.external_id }} ROLE_TO_ASSUME={{ $environment.role_to_assume }} AWS_ACCOUNT={{ $environment.account }} source .gitlab/scripts/get_secrets.sh
  script:
    - LAYER_FILE=datadog_lambda_ruby-{{ $runtime.arch}}-{{ $runtime.ruby_version }}.zip ./scripts/sign_layers.sh {{ $environment.name }}
{{ end }}

publish layer {{ $environment.name }} ({{ $runtime.name }}, {{ $runtime.arch }}):
  stage: publish
  tags: ["arch:amd64"]
  image: registry.ddbuild.io/images/docker:20.10-py3
  rules:
    - if: '"{{ $environment.name }}" =~ /^(sandbox|staging)/'
      when: manual
      allow_failure: true
    - if: '$CI_COMMIT_TAG =~ /^v.*/'
  needs:
{{ if or (eq $environment.name "prod") }}
      - sign layer ({{ $runtime.name }}, {{ $runtime.arch }})
{{ else }}
      - build layer ({{ $runtime.name }}, {{ $runtime.arch }})
      - check layer size ({{ $runtime.name }}, {{ $runtime.arch }})
      - lint ({{$runtime.name}}, {{ $runtime.arch }})
      - unit test ({{ $runtime.name }}, {{ $runtime.arch }})
      - integration test ({{ $runtime.name }}, {{ $runtime.arch }})
{{ end }}
  dependencies:
{{ if or (eq $environment.name "prod") }}
      - sign layer ({{ $runtime.name }}, {{ $runtime.arch }})
{{ else }}
      - build layer ({{ $runtime.name }}, {{ $runtime.arch }})
{{ end }}
  parallel:
    matrix:
      - REGION: {{ range (ds "regions").regions }}
          - {{ .code }}
        {{- end}}
  before_script:
    - EXTERNAL_ID_NAME={{ $environment.external_id }} ROLE_TO_ASSUME={{ $environment.role_to_assume }} AWS_ACCOUNT={{ $environment.account }} source .gitlab/scripts/get_secrets.sh
  script:
    - STAGE={{ $environment.name }} RUBY_VERSION={{ $runtime.ruby_version }} ARCH={{ $runtime.arch }} .gitlab/scripts/publish_layer.sh

{{- end }}

{{- end }}

publish rubygems:
  stage: publish
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  cache: []
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v.*/'
  when: manual
  needs: {{ range $runtime := (ds "runtimes").runtimes }}
    - sign layer ({{ $runtime.name }}, {{ $runtime.arch}})
  {{- end }}
  script:
    - .gitlab/scripts/publish_rubygems.sh