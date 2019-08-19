# frozen_string_literal: true

require 'ddlambda/trace/context'

describe DDLambda::Trace do
  it 'converts an xray trace id to a Datadog trace ID' do
    xray_trace_id = '1-5ce31dc2-ffffffff390ce44db5e03875'
    trace_id = DDLambda::Trace.convert_xray_to_apm_trace_id(xray_trace_id)
    expect(trace_id).to eq('4110911582297405557')
  end

  it 'converts an xray trace id to a Datadog trace ID by only taking last 63 bits' do
    # 64th bit is 1, (b -> [1]011), gets cropped off
    xray_trace_id = '1-5ce31dc2-ffffffffb90ce44db5e03875'
    trace_id = DDLambda::Trace.convert_xray_to_apm_trace_id(xray_trace_id)
    expect(trace_id).to eq('4110911582297405557')
  end

  it 'returns nil when xray trace id is too short' do
    xray_trace_id = '1-5ce31dc2-5e03875'
    trace_id = DDLambda::Trace.convert_xray_to_apm_trace_id(xray_trace_id)
    expect(trace_id).to eq(nil)
  end

  it 'returns nil when xray trace id is in an invalid format' do
    xray_trace_id = '1-2c779014b90ce44db5e03875'
    trace_id = DDLambda::Trace.convert_xray_to_apm_trace_id(xray_trace_id)
    expect(trace_id).to eq(nil)
  end

  it 'returns nil when xray trace id uses invalid characters' do
    xray_trace_id = '1-5ce31dc2-c779014b90ce44db5e03875;'
    trace_id = DDLambda::Trace.convert_xray_to_apm_trace_id(xray_trace_id)
    expect(trace_id).to eq(nil)
  end

  it 'converts an xray parent ID to an APM parent ID' do
    xray_parent_id = '0b11cc4230d3e09e'
    parent_id = DDLambda::Trace.convert_xray_parent_id_to_apm_parent_id(xray_parent_id)
    expect(parent_id).to eq('797643193680388254')
  end

  it 'returns nil when parent ID uses invalid characters' do
    xray_parent_id = ';79014b90ce44db5e0;875'
    parent_id = DDLambda::Trace.convert_xray_parent_id_to_apm_parent_id(xray_parent_id)
    expect(parent_id).to eq(nil)
  end
  it 'returns undefined when parent ID is wrong size' do
    xray_parent_id = '5e03875'
    parent_id = DDLambda::Trace.convert_xray_parent_id_to_apm_parent_id(xray_parent_id)
    expect(parent_id).to eq(nil)
  end
end
