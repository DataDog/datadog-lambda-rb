# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
require 'datadog/lambda'
require 'datadog/lambda/trace/constants'
require_relative './lambdacontext'
require_relative './lambdacontextversion'
require_relative './lambdacontextalias'

describe Datadog::Lambda do
  ctx = LambdaContext.new
  let(:layer_tag) { RUBY_VERSION[0, 3].tr('.', '') }
  let(:default_tags) { ["dd_lambda_layer:datadog-ruby#{layer_tag}"] }

  context 'enhanced tags' do
    it 'recognizes a cold start' do
      expect(Datadog::Lambda.gen_enhanced_tags(ctx)[:cold_start]).to eq(true)
    end
  end

  describe '#wrap' do
    context 'with a handler that raises an error' do
      subject { Datadog::Lambda.wrap(event, context) { raise 'Error' } }
      let(:event) { '1' }
      let(:context) { ctx }

      it 'should raise an error if the block raises an error' do
        expect { subject }.to raise_error 'Error'
      end
    end

    context 'with a succesful handler' do
      subject { Datadog::Lambda.wrap(event, context) { { result: 100 } } }
      let(:event) { '1' }
      let(:context) { ctx }

      it 'should return the same value as returned by the block' do
        expect(subject[:result]).to be 100
      end
    end

    context 'with a handler that sends a custom metric' do
      subject(:handler) do
        Datadog::Lambda.wrap(event, context) do
          Datadog::Lambda.metric('m1', 100, env: 'dev', region: 'nyc')
          { result: 100 }
        end
      end
      let(:event) { '1' }
      let(:context) { ctx }
      let(:metrics_client) { Datadog::Lambda.instance_variable_get(:@metrics_client) }

      it 'should print metric and close the client' do
        # Mock first distribution call which is for enhanced metrics
        expect(metrics_client).to receive(:distribution)
        # Mock second call which is our custom metric
        expect(metrics_client).to receive(:distribution).with('m1', 100, time: nil, env: 'dev', region: 'nyc')
        expect(metrics_client).to receive(:close)
        expect(handler[:result]).to be 100
      end
    end
  end

  context 'enhanced tags' do
    it 'recognizes an error as having warmed the environment' do
      expect(Datadog::Lambda.gen_enhanced_tags(ctx)[:cold_start]).to eq(false)
    end
  end

  context 'trace_context' do
    it 'should return the last trace context' do
      event = {
        'headers' => {
          'x-datadog-trace-id' => '12345',
          'x-datadog-parent-id' => '45678',
          'x-datadog-sampling-priority' => '2'
        }
      }
      Datadog::Lambda.wrap(event, ctx) do
        { result: 100 }
      end
      expect(Datadog::Lambda.trace_context).to eq(
        trace_id: '12345',
        parent_id: '45678',
        sample_mode: 2,
        source: Datadog::Trace::SOURCE_EVENT
      )
    end
  end
  context 'enhanced tags' do
    it 'makes tags from a Lambda context' do
      ctx = LambdaContext.new
      expect(Datadog::Lambda.gen_enhanced_tags(ctx)).to include(
        account_id: '172597598159',
        cold_start: false,
        functionname: "hello-dog-ruby-dev-helloRuby#{layer_tag}",
        memorysize: 128,
        region: 'us-east-1',
        resource: "hello-dog-ruby-dev-helloRuby#{layer_tag}"
      )
    end
  end
  context 'enhanced tags Version' do
    it 'makes tags from a Lambda context with $Latest' do
      ctxv = LambdaContextVersion.new
      expect(Datadog::Lambda.gen_enhanced_tags(ctxv)).to include(
        { account_id: '172597598159',
          cold_start: false,
          functionname: 'Ruby-test',
          memorysize: 128,
          region: 'us-east-1',
          resource: 'Ruby-test:1' }
      )
    end
  end
  context 'enhanced tags with an alias' do
    it 'makes tags from a Lambda context with an alias' do
      ctxa = LambdaContextAlias.new
      expect(Datadog::Lambda.gen_enhanced_tags(ctxa)).to include(
        { account_id: '172597598159',
          cold_start: false,
          functionname: 'Ruby-test',
          memorysize: 128,
          region: 'us-east-1',
          resource: 'Ruby-test:my-alias',
          executedversion: '1' }
      )
    end
  end

  describe '#metric' do
    context 'when extension is running' do
      subject(:lambdaModule) { Datadog::Lambda }
      subject(:metrics_client) { lambdaModule.instance_variable_get(:@metrics_client) }
      let(:statsd) { instance_double(Datadog::Statsd) }

      before(:each) do
        # Stub the extension_running? method to return true
        allow(Datadog::Utils).to receive(:extension_running?).and_return(true)

        # Mock Datadog::Statsd client
        @previous_statsd = metrics_client.instance_variable_get(:@statsd)
        metrics_client.instance_variable_set(:@statsd, statsd)
      end

      after(:each) do
        # Reset Datadog::Statsd mock
        metrics_client.instance_variable_set(:@statsd, @previous_statsd)
      end

      it 'sends metrics properly' do
        # Expect the metric method to be called with the correct arguments
        expect(lambdaModule).to receive(:metric).with('metric_name', 42, env: 'dev', region: 'nyc')

        # Call the distribution method
        lambdaModule.metric('metric_name', 42, env: 'dev', region: 'nyc')
      end
    end

    context 'when extension is not running' do
      it 'prints a custom metric' do
        now = Time.utc(2008, 7, 8, 9, 10)
        expect(Time).to receive(:now).and_return(now)

        output = %({"e":1215508200,"m":"m1","t":["dd_lambda_layer:datadog-ruby#{layer_tag}","t.b:v2"],"v":100})
        expect do
          Datadog::Lambda.metric('m1', 100, "t.b": 'v2')
        end.to output("#{output}\n").to_stdout
      end

      it 'prints a custom metric with a custom timestamp' do
        custom_time = Time.utc(2008, 7, 8, 9, 11)

        output = %({"e":1215508260,"m":"m1","t":["dd_lambda_layer:datadog-ruby#{layer_tag}","t.b:v2"],"v":100})
        expect do
          Datadog::Lambda.metric('m1', 100, time: custom_time, "t.b": 'v2')
        end.to output("#{output}\n").to_stdout
      end
    end
  end

  context 'enhanced metrics' do
    it 'correctly reads the DD_ENHANCED_METRICS env var' do
      allow(ENV).to receive(:[]).with('DD_ENHANCED_METRICS').and_return('true')
      expect(Datadog::Lambda.do_enhanced_metrics?).to eq(true)
    end
    it 'correctly reads the DD_ENHANCED_METRICS env var regardless of case' do
      allow(ENV).to receive(:[]).with('DD_ENHANCED_METRICS').and_return('True')
      expect(Datadog::Lambda.do_enhanced_metrics?).to eq(true)
    end
    it 'correctly reads false DD_ENHANCED_METRICS as false' do
      allow(ENV).to receive(:[]).with('DD_ENHANCED_METRICS').and_return('false')
      expect(Datadog::Lambda.do_enhanced_metrics?).to eq(false)
    end
    it 'correctly reads lack of DD_ENHANCED_METRICS as false' do
      allow(ENV).to receive(:[]).with('DD_ENHANCED_METRICS').and_return('false')
      expect(Datadog::Lambda.do_enhanced_metrics?).to eq(false)
    end
  end
  context 'enhanced metrics' do
    it 'does not submit enhanced metrics if DD_ENHANCED_METRICS is false' do
      allow(ENV).to receive(:[]).with('DD_ENHANCED_METRICS').and_return('false')
      expect(Datadog::Lambda.record_enhanced('foo', ctx)).to eq(false)
    end
    it 'submits enhanced metrics if DD_ENHANCED_METRICS is true' do
      allow(ENV).to receive(:[]).with('DD_ENHANCED_METRICS').and_return('true')
      expect(Datadog::Lambda.record_enhanced('foo', ctx)).to eq(true)
    end
  end
  context 'enhanced metrics output' do
    it 'prints enhanced metrics to the logs' do
      allow(ENV).to receive(:[]).with('DD_ENHANCED_METRICS').and_return('true')
      # rubocop:disable Metrics/LineLength
      expect do
        Datadog::Lambda.record_enhanced('invocations', ctx)
      end.to output(/"dd_lambda_layer:datadog-ruby#{layer_tag}","functionname:hello-dog-ruby-dev-helloRuby#{layer_tag}","region:us-east-1","account_id:172597598159","memorysize:128",/).to_stdout
      # rubocop:enable Metrics/LineLength
    end
  end
end

# rubocop:enable Metrics/BlockLength
