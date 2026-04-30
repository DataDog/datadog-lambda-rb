# frozen_string_literal: true

require 'datadog/lambda/utils/version'

RSpec.describe Datadog::Utils, '.dd_trace_version' do
  subject(:version) { described_class.dd_trace_version }

  context 'when datadog gem is loaded' do
    it { expect(version).to match(/\A\d+\.\d+\.\d+/) }
  end

  context 'when datadog gem is not available' do
    before do
      allow(Gem).to receive(:loaded_specs).and_raise(StandardError)
      allow(Datadog::Utils.logger).to receive(:debug)
    end

    it { expect(version).to be_nil }

    it 'logs a debug message' do
      version
      expect(Datadog::Utils.logger).to have_received(:debug).with('datadog unavailable')
    end
  end
end
