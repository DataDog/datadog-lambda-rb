# frozen_string_literal: true

require 'datadog/lambda/trace/listener'

RSpec.describe Datadog::Trace::Listener do
  subject(:listener) do
    described_class.new(handler_name: 'h', function_name: 'f', patch_http: false, merge_xray_traces: false)
  end

  describe '#with_appsec' do
    context 'when a request-phase override is present' do
      before { listener.instance_variable_set(:@response_override, {'statusCode' => 403}) }

      it { expect(listener.with_appsec { 'handler' }).to eq({'statusCode' => 403}) }

      it 'does not run the handler' do
        expect { |b| listener.with_appsec(&b) }.not_to yield_control
      end
    end

    context 'when no override is present' do
      before { allow(Datadog::Lambda::AppSec).to receive(:catch_interrupt) { |&blk| blk.call } }

      it { expect(listener.with_appsec { 'handler' }).to eq('handler') }
    end
  end
end
