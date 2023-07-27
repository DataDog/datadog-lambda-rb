# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
require 'datadog/lambda'
require 'datadog/statsd'
require 'datadog/lambda/metrics'
require 'datadog/lambda/utils/logger'

describe Datadog::Metrics::Client do
  subject(:client) { Datadog::Metrics::Client.instance }
  let(:layer_tag) { Datadog::Lambda.dd_lambda_layer_tag }
  let(:default_tags) { ["dd_lambda_layer:datadog-ruby#{layer_tag}"] }

  describe '.instance' do
    it 'returns the same instance' do
      instance1 = Datadog::Metrics::Client.instance
      instance2 = Datadog::Metrics::Client.instance
      expect(instance1).to be(instance2)
    end
  end

  describe '#distribution' do
    context 'when extension is running' do
      let(:statsd) { instance_double(Datadog::Statsd) }

      before(:each) do
        # Mock the extension_running? method to return true
        allow(Datadog::Utils).to receive(:extension_running?).and_return(true)

        # Mock Datadog::Statsd client
        @previous_statsd = client.instance_variable_get(:@statsd)
        client.instance_variable_set(:@statsd, statsd)
      end

      after(:each) do
        # Reset Datadog::Statsd mock
        client.instance_variable_set(:@statsd, @previous_statsd)
      end

      it 'sends metrics properly' do
        expected_tags = default_tags.concat(['env:dev', 'region:nyc'])
        # Expect the distribution method to be called with the correct arguments
        expect(statsd).to receive(:distribution).with('metric_name', 42, tags: expected_tags)

        # Call the distribution method
        client.distribution('metric_name', 42, env: 'dev', region: 'nyc')
      end

      it 'doesnt send metric when statsd fails' do
        expect(statsd).to receive(:distribution).and_raise 'not sending metric!'

        expected = 'error sending metric to the extension: not sending metric!'
        expect(Datadog::Utils.logger).to receive(:warning).with(expected)

        # Call the distribution method, which should raise the specified error
        # and the logger should print it as debug
        client.distribution('metric_name', 42, env: 'dev', region: 'nyc')
      end
    end

    it 'doesnt send metric when statsd fails' do
      allow(Datadog::Utils).to receive(:extension_running?).and_return(true)

      statsd = instance_double(Datadog::Statsd)
      previous_statsd = client.instance_variable_get(:@statsd)
      client.instance_variable_set(:@statsd, statsd)

      expected_tags = default_tags.concat(['env:dev', 'region:nyc'])
      # Expect the distribution method to be called with the correct arguments
      expect(statsd).to receive(:distribution).with('metric_name', 42, tags: expected_tags)

      # Call the distribution method
      client.distribution('metric_name', 42, env: 'dev', region: 'nyc')

      # Reset Datadog::Statsd mock
      client.instance_variable_set(:@statsd, previous_statsd)
    end

    it 'prints metrics when extension is not running' do
      # Mock the extension_running? method to return false
      allow(Datadog::Utils).to receive(:extension_running?).and_return(false)

      now = Time.utc(2023, 1, 7, 12, 30)
      allow(Time).to receive(:now).and_return(now)

      output = %({"e":1673094600,"m":"metric_name","t":["dd_lambda_layer:datadog-ruby#{layer_tag}","env:dev"],"v":42})
      # Expect the metric to be printed to console (you may want to use an appropriate matcher for this)
      expect { client.distribution('metric_name', 42, env: 'dev') }.to output("#{output}\n").to_stdout
    end
  end

  describe '#get_tags' do
    context 'when there a no tags' do
      it 'should return the default tags' do
        expect(client.get_tags).to match_array(default_tags)
      end
    end

    context 'when tags are included' do
      it 'should add the default tags to the sent ones' do
        expected_tags = default_tags.concat(['env:dev', 'region:nyc'])
        expect(client.get_tags(env: 'dev', region: 'nyc')).to match_array(expected_tags)
      end
    end
  end
end

# rubocop:enable Metrics/BlockLength
