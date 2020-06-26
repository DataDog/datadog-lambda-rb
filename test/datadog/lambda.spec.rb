# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
require 'datadog/lambda'
require_relative './lambdacontext'
require_relative './lambdacontextversion'
require_relative './lambdacontextalias'

describe Datadog::Lambda do
  ctx = LambdaContext.new
  context 'enhanced tags' do
    it 'recognizes a cold start' do
      expect(Datadog::Lambda.gen_enhanced_tags(ctx)[:cold_start]).to eq(true)
    end
  end
  context 'with a handler that raises an error' do
    subject { Datadog::Lambda.wrap(event, context) { raise 'Error' } }
    let(:event) { '1' }
    let(:context) { ctx }

    it 'should raise an error if the block raises an error' do
      expect { subject }.to raise_error 'Error'
    end
  end
  context 'with a handler that raises a NoMemoryError' do
    subject { Datadog::Lambda.wrap(event, context) { raise NoMemoryError } }
    let(:event) { '1' }
    let(:context) { ctx }

    it 'should raise a NoMemoryError error and print an error message if the block raises a NoMemoryError' do
      expect { subject }
        .to raise_error(NoMemoryError)
        .and output(/from Datadog Lambda Layer\: failed to allocate memory \(NoMemoryError\)/).to_stdout
    end
  end
  context 'enhanced tags' do
    it 'recognizes an error as having warmed the environment' do
      expect(Datadog::Lambda.gen_enhanced_tags(ctx)[:cold_start]).to eq(false)
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
        sample_mode: 2
      )
    end
  end
  context 'enhanced tags' do
    it 'makes tags from a Lambda context' do
      ctx = LambdaContext.new
      expect(Datadog::Lambda.gen_enhanced_tags(ctx)).to include(
        account_id: '172597598159',
        cold_start: false,
        functionname: 'hello-dog-ruby-dev-helloRuby25',
        memorysize: 128,
        region: 'us-east-1',
        runtime: include('Ruby 2.'),
        resource: 'hello-dog-ruby-dev-helloRuby25'
      )
    end
  end
  context 'enhanced tags Version' do
    it 'makes tags from a Lambda context with $Latest' do
      ctxv = LambdaContextVersion.new
      expect(Datadog::Lambda.gen_enhanced_tags(ctxv)).to include(
        { account_id: '172597598159',
          cold_start: false,
          functionname: 'ruby-test',
          memorysize: 128,
          region: 'us-east-1',
          resource: 'ruby-test:Latest',
          runtime: include('Ruby 2.') }
      )
    end
  end
  context 'enhanced tags with an alias' do
    it 'makes tags from a Lambda context with an alias' do
      ctxa = LambdaContextAlias.new
      expect(Datadog::Lambda.gen_enhanced_tags(ctxa)).to include(
        { account_id: '172597598159',
          cold_start: false,
          functionname: 'ruby-test',
          memorysize: 128,
          region: 'us-east-1',
          resource: 'ruby-test:my-alias',
          executedversion: '1',
          runtime: include('Ruby 2.') }
      )
    end
  end
  context 'metric' do
    it 'prints a custom metric' do
      now = Time.utc(2008, 7, 8, 9, 10)

      output = '{"e":1215508200,"m":"m1","t":["dd_lambda_layer:datadog-ruby25","t.a:val","t.b:v2"],"v":100}'
      expect(Time).to receive(:now).and_return(now)
      expect do
        Datadog::Lambda.metric('m1', 100, "t.a": 'val', "t.b": 'v2')
      end.to output("#{output}\n").to_stdout
    end
    it 'prints a custom metric with a custom timestamp' do
      custom_time = Time.utc(2008, 7, 8, 9, 11)
      output = '{"e":1215508260,"m":"m1","t":["dd_lambda_layer:datadog-ruby25","t.a:val","t.b:v2"],"v":100}'
      expect do
        Datadog::Lambda.metric('m1', 100, time: custom_time, "t.a": 'val', "t.b": 'v2')
      end.to output("#{output}\n").to_stdout
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
      end.to output(/"dd_lambda_layer:datadog-ruby25","functionname:hello-dog-ruby-dev-helloRuby25","region:us-east-1","account_id:172597598159","memorysize:128",/).to_stdout
      # rubocop:enable Metrics/LineLength
    end
  end
end

# rubocop:enable Metrics/BlockLength
