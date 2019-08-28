#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

# frozen_string_literal: true

module Datadog
  module Trace
    SAMPLE_MODE_USER_REJECT = -1
    SAMPLE_MODE_AUTO_REJECT = 0
    SAMPLE_MODE_AUTO_KEEP = 1
    SAMPLE_MODE_USER_KEEP = 2
    DD_TRACE_ID_HEADER = 'x-datadog-trace-id'
    DD_PARENT_ID_HEADER = 'x-datadog-parent-id'
    DD_SAMPLING_PRIORITY_HEADER = 'x-datadog-sampling-priority'
    DD_XRAY_SUBSEGMENT_NAME = 'datadog-metadata'
    DD_XRAY_SUBSEGMENT_KEY = 'trace'
    DD_XRAY_SUBSEGMENT_NAMESPACE = 'datadog'
  end
end