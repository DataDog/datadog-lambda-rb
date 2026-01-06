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

build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }}):
  stage: build
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  artifacts:
    expire_in: 1 hr # Unsigned zips expire in 1 hour
    paths:
      - .layers/datadog-lambda_ruby-{{ $runtime.arch }}-{{ $runtime.ruby_version }}.zip
  script:
    - RUBY_VERSION={{ $runtime.ruby_version }} ARCH={{ $runtime.arch }} .gitlab/scripts/build_layer.sh

check layer size ({{ $runtime.ruby_version }}, {{ $runtime.arch }}):
  stage: test
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  needs: 
    - build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
  dependencies:
    - build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
  script: 
    - RUBY_VERSION={{ $runtime.ruby_version }} ARCH={{ $runtime.arch }} ./scripts/check_layer_size.sh

lint ({{$runtime.ruby_version}}, {{ $runtime.arch }}):
  stage: test
  tags: ["arch:amd64"]
  image: registry.ddbuild.io/images/mirror/ruby:{{ $runtime.image }}
  needs: []
  cache: &{{ $runtime.name }}-{{ $runtime.arch }}-cache
  script: 
    - bundle install
    - bundle exec rubocop

unit test ({{ $runtime.ruby_version }}, {{ $runtime.arch }}):
  stage: test
  tags: ["arch:amd64"]
  image: registry.ddbuild.io/images/mirror/ruby:{{ $runtime.image }}
  needs: []
  cache: &{{ $runtime.name }}-{{ $runtime.arch }}-cache
  script: 
    - bundle install
    - bundle exec rake test

integration test ({{ $runtime.ruby_version }}, {{ $runtime.arch }}):
  stage: test
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  needs: 
    - build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
  dependencies:
    - build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
  cache: &{{ $runtime.name }}-{{ $runtime.arch }}-cache
  before_script:
    - EXTERNAL_ID_NAME=integration-test-externalid ROLE_TO_ASSUME=sandbox-integration-test-deployer AWS_ACCOUNT=425362996713 source .gitlab/scripts/get_secrets.sh
    - cd integration_tests && yarn install && cd ..
  script:
    - RUNTIME_PARAM={{ $runtime.ruby_version }} ARCH={{ $runtime.arch }} ./scripts/run_integration_tests.sh

sign layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }}):
  stage: sign
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v.*/'
      when: manual
  needs:
    - build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
    - check layer size ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
    - lint ({{$runtime.ruby_version}}, {{ $runtime.arch }})
    - unit test ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
    - integration test ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
  dependencies:
    - build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
  artifacts: # Re specify artifacts so the modified signed file is passed
    expire_in: 1 day # Signed layers should expire after 1 day
    paths:
      - .layers/datadog-lambda_ruby-{{ $runtime.arch }}-{{ $runtime.ruby_version }}.zip
  before_script:
    {{ with $environment := (ds "environments").environments.prod }}
    - EXTERNAL_ID_NAME={{ $environment.external_id }} ROLE_TO_ASSUME={{ $environment.role_to_assume }} AWS_ACCOUNT={{ $environment.account }} source .gitlab/scripts/get_secrets.sh
    {{ end }}
  script:
    - LAYER_FILE=datadog-lambda_ruby-{{ $runtime.arch}}-{{ $runtime.ruby_version }}.zip ./scripts/sign_layers.sh prod

{{ range $environment_name, $environment := (ds "environments").environments }}

publish layer {{ $environment_name }} ({{ $runtime.ruby_version }}, {{ $runtime.arch }}):
  stage: publish
  tags: ["arch:amd64"]
  image: registry.ddbuild.io/images/docker:20.10-py3
  rules:
    - if: '"{{ $environment_name }}" == "sandbox"'
      when: manual
      allow_failure: true
    - if: '$CI_COMMIT_TAG =~ /^v.*/'
  needs:
{{ if eq $environment_name "prod" }}
      - sign layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
{{ else }}
      - build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
      - check layer size ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
      - lint ({{$runtime.ruby_version}}, {{ $runtime.arch }})
      - unit test ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
      - integration test ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
{{ end }}
  dependencies:
{{ if eq $environment_name "prod" }}
      - sign layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
{{ else }}
      - build layer ({{ $runtime.ruby_version }}, {{ $runtime.arch }})
{{ end }}
  parallel:
    matrix:
      - REGION: {{ range (ds "regions").regions }}
          - {{ .code }}
        {{- end}}
  before_script:
    - EXTERNAL_ID_NAME={{ $environment.external_id }} ROLE_TO_ASSUME={{ $environment.role_to_assume }} AWS_ACCOUNT={{ $environment.account }} source .gitlab/scripts/get_secrets.sh
  script:
    - STAGE={{ $environment_name }} RUBY_VERSION={{ $runtime.ruby_version }} ARCH={{ $runtime.arch }} .gitlab/scripts/publish_layer.sh

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
    - sign layer ({{ $runtime.ruby_version }}, {{ $runtime.arch}})
  {{- end }}
  script:
    - .gitlab/scripts/publish_rubygems.sh

layer bundle:
  stage: build
  tags: ["arch:amd64"]
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  needs:
    {{ range (ds "runtimes").runtimes }}
    - build layer ({{ .ruby_version }}, {{ .arch }})
    {{ end }}
  dependencies:
    {{ range (ds "runtimes").runtimes }}
    - build layer ({{ .ruby_version }}, {{ .arch }})
    {{ end }}
  artifacts:
    expire_in: 1 hr
    paths:
      - datadog-lambda_ruby-bundle-${CI_JOB_ID}/
    name: datadog-lambda_ruby-bundle-${CI_JOB_ID}
  script:
    - rm -rf datadog-lambda_ruby-bundle-${CI_JOB_ID}
    - mkdir -p datadog-lambda_ruby-bundle-${CI_JOB_ID}
    - cp .layers/datadog-lambda_ruby-*.zip datadog-lambda_ruby-bundle-${CI_JOB_ID}

signed layer bundle:
  stage: sign
  image: ${CI_DOCKER_TARGET_IMAGE}:${CI_DOCKER_TARGET_VERSION}
  tags: ["arch:amd64"]
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v.*/'
  needs:
    {{ range (ds "runtimes").runtimes }}
    - sign layer ({{ .ruby_version }}, {{ .arch }})
    {{ end }}
  dependencies:
    {{ range (ds "runtimes").runtimes }}
    - sign layer ({{ .ruby_version }}, {{ .arch }})
    {{ end }}
  artifacts:
    expire_in: 1 day
    paths:
      - datadog-lambda_ruby-signed-bundle-${CI_JOB_ID}/
    name: datadog-lambda_ruby-signed-bundle-${CI_JOB_ID}
  script:
    - rm -rf datadog-lambda_ruby-signed-bundle-${CI_JOB_ID}
    - mkdir -p datadog-lambda_ruby-signed-bundle-${CI_JOB_ID}
    - cp .layers/datadog-lambda_ruby-*.zip datadog-lambda_ruby-signed-bundle-${CI_JOB_ID}
