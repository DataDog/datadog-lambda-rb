# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require 'datadog/lambda/trace/context'
require 'datadog/lambda/trace/constants'
require 'socket'

describe Datadog::Trace do
  context 'read_trace_context_from_event' do
    it 'can read well formed event with headers' do
      event = {
        'headers' => {
          'x-datadog-parent-id' => '797643193680388254',
          'x-datadog-sampling-priority' => '2',
          'x-datadog-trace-id' => '4110911582297405557'
        }
      }
      res = Datadog::Trace.read_trace_context_from_event(event)
      expect(res).to eq(
        trace_id: '4110911582297405557',
        parent_id: '797643193680388254',
        sample_mode: Datadog::Trace::SAMPLE_MODE_USER_KEEP,
        source: Datadog::Trace::SOURCE_EVENT
      )
    end

    it 'can read well formed headers with mixed casing' do
      event = {
        'headers' => {
          'X-Datadog-Parent-Id' => '797643193680388254',
          'X-Datadog-Sampling-Priority' => '2',
          'X-Datadog-Trace-Id' => '4110911582297405557'
        }
      }
      res = Datadog::Trace.read_trace_context_from_event(event)
      expect(res).to eq(
        trace_id: '4110911582297405557',
        parent_id: '797643193680388254',
        sample_mode: Datadog::Trace::SAMPLE_MODE_USER_KEEP,
        source: Datadog::Trace::SOURCE_EVENT
      )
    end

    it 'returns nil when missing trace id' do
      event = {
        'headers' => {
          'x-datadog-parent-id' => '797643193680388254',
          'x-datadog-sampling-priority' => '2'
        }
      }
      res = Datadog::Trace.read_trace_context_from_event(event)
      expect(res).to eq(nil)
    end
    it 'returns nil when missing parent id' do
      event = {
        'headers' => {
          'x-datadog-sampling-priority' => '2',
          'x-datadog-trace-id' => '4110911582297405557'
        }
      }
      res = Datadog::Trace.read_trace_context_from_event(event)
      expect(res).to eq(nil)
    end
    it 'returns nil when missing sampling priority' do
      event = {
        'headers' => {
          'x-datadog-parent-id' => '797643193680388254',
          'x-datadog-trace-id' => '4110911582297405557'
        }
      }
      res = Datadog::Trace.read_trace_context_from_event(event)
      expect(res).to eq(nil)
    end
    it 'returns nil when missing header values' do
      event = {}
      res = Datadog::Trace.read_trace_context_from_event(event)
      expect(res).to eq(nil)
    end
    it 'returns nil when event isn\'t and object' do
      event = 'some-value'
      res = Datadog::Trace.read_trace_context_from_event(event)
      expect(res).to eq(nil)
    end
  end

  context 'convert_to_apm_trace_id' do
    it 'converts an xray trace id to a APM trace ID' do
      xray_trace_id = '1-5ce31dc2-ffffffff390ce44db5e03875'
      trace_id = Datadog::Trace.convert_to_apm_trace_id(xray_trace_id)
      expect(trace_id).to eq('4110911582297405557')
    end

    it 'converts an xray trace id to a APM trace ID by taking last 63 bits' do
      # 64th bit is 1, (b -> [1]011), gets cropped off
      xray_trace_id = '1-5ce31dc2-ffffffffb90ce44db5e03875'
      trace_id = Datadog::Trace.convert_to_apm_trace_id(xray_trace_id)
      expect(trace_id).to eq('4110911582297405557')
    end

    it 'returns nil when xray trace id is too short' do
      xray_trace_id = '1-5ce31dc2-5e03875'
      trace_id = Datadog::Trace.convert_to_apm_trace_id(xray_trace_id)
      expect(trace_id).to eq(nil)
    end

    it 'returns nil when xray trace id is in an invalid format' do
      xray_trace_id = '1-2c779014b90ce44db5e03875'
      trace_id = Datadog::Trace.convert_to_apm_trace_id(xray_trace_id)
      expect(trace_id).to eq(nil)
    end
    it 'returns nil when xray trace id uses invalid characters' do
      xray_trace_id = '1-5ce31dc2-c779014b90ce44db5e03875;'
      trace_id = Datadog::Trace.convert_to_apm_trace_id(xray_trace_id)
      expect(trace_id).to eq(nil)
    end
  end

  context 'convert_to_apm_trace_id' do
    it 'converts an xray parent ID to an APM parent ID' do
      xray_parent_id = '0b11cc4230d3e09e'
      parent_id = Datadog::Trace.convert_to_apm_parent_id(xray_parent_id)
      expect(parent_id).to eq('797643193680388254')
    end

    it 'returns nil when parent ID uses invalid characters' do
      xray_parent_id = ';79014b90ce44db5e0;875'
      parent_id = Datadog::Trace.convert_to_apm_parent_id(xray_parent_id)
      expect(parent_id).to eq(nil)
    end
    it 'returns undefined when parent ID is wrong size' do
      xray_parent_id = '5e03875'
      parent_id = Datadog::Trace.convert_to_apm_parent_id(xray_parent_id)
      expect(parent_id).to eq(nil)
    end
  end

  context 'read_trace_context_from_xray' do
    after(:all) { ENV.delete(Datadog::Trace::XRAY_ENV_VAR) }
    it 'reads the parent id and trace id from X-Ray' do
      trace_id = '1-5ce31dc2-ffffffff390ce44db5e03875'
      parent_id = '0b11cc4230d3e09e'
      ENV[Datadog::Trace::XRAY_ENV_VAR] =
        "Root=#{trace_id};Parent=#{parent_id};Sampled=1"
      res = Datadog::Trace.read_trace_context_from_xray
      expect(res).to eq(
        trace_id: '4110911582297405557',
        parent_id: '797643193680388254',
        sample_mode: Datadog::Trace::SAMPLE_MODE_USER_KEEP,
        source: Datadog::Trace::SOURCE_XRAY
      )
    end
  end

  context 'extract_trace_context' do
    after(:all) { ENV.delete(Datadog::Trace::XRAY_ENV_VAR) }

    it 'writes metadata to X-Ray if tracing headers are on event' do
      trace_id = '1-5ce31dc2-ffffffff390ce44db5e03875'
      parent_id = '0b11cc4230d3e09e'
      ENV[Datadog::Trace::XRAY_ENV_VAR] =
        "Root=#{trace_id};Parent=#{parent_id};Sampled=1"

      socket = UDPSocket.open

      expect(UDPSocket).to receive(:open).and_return(socket)
      expect(socket).to receive(:send).with(
        include('parent-id":"797643193680388254","sampling-priority":"2","trace-id":"4110911582297405557"'),
        0,
        '127.0.0.1',
        2000
      )

      event = {
        'headers' => {
          'X-Datadog-Parent-Id' => '797643193680388254',
          'X-Datadog-Sampling-Priority' => '2',
          'X-Datadog-Trace-Id' => '4110911582297405557'
        }
      }
      res = Datadog::Trace.extract_trace_context(event, true)
      expect(res).to eq(
        trace_id: '4110911582297405557',
        parent_id: '797643193680388254',
        sample_mode: Datadog::Trace::SAMPLE_MODE_USER_KEEP,
        source: Datadog::Trace::SOURCE_EVENT
      )
    end
  end
end

# rubocop:enable Metrics/BlockLength
