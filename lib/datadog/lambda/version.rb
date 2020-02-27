# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

module Datadog
  module Lambda
    module VERSION
      MAJOR = 0
      MINOR = 7
      PATCH = 0
      PRE = nil

      STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')
    end
  end
end
