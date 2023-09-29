# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

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
    DD_TRACE_MANAGED_SERVICES = 'DD_TRACE_MANAGED_SERVICES'
    SOURCE_XRAY = 'XRAY'
    SOURCE_EVENT = 'EVENT'
    XRAY_ENV_VAR = '_X_AMZN_TRACE_ID'
    XRAY_UDP_PORT = 2000
    LOCAL_HOST = '127.0.0.1'
    AWS_XRAY_DAEMON_ADDRESS_ENV_VAR = 'AWS_XRAY_DAEMON_ADDRESS'

    # Header that prevents dd-trace-rb Net::HTTP integration from tracing
    # internal trace requests. Set it to any value to skip tracing.
    HEADER_DD_INTERNAL_UNTRACED_REQUEST = 'DD-Internal-Untraced-Request'
  end
end
