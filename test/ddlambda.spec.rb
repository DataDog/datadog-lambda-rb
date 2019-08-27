# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require 'ddlambda'

describe DDLambda do
  it 'should return the same value as returned by wrap' do
    event = '1'
    context = '2'
    res = DDLambda.wrap(event, context) do
      { result: 100 }
    end
    expect(res[:result]).to be 100
  end
  it 'should raise an error if the block raises an error' do
    error_raised = false
    begin
      DDLambda.wrap(event, context) do
        raise 'Error'
      end
    rescue StandardError
      error_raised = true
    end
    expect(error_raised).to be true
  end
  context 'metric' do
    it 'prints a custom metric' do
      now = Time.utc(2008, 7, 8, 9, 10)
      output = '{"e":121550820000,"m":"m1","t":["t.a:value","t.b:v2"],"v":100}'
      expect(Time).to receive(:now).and_return(now)
      expect do
        DDLambda.metric('m1', 100, "t.a": 'value', "t.b": 'v2')
      end.to output("#{output}\n").to_stdout
    end
    it 'prints a custom metric with a custom timestamp' do
      now = Time.utc(2008, 7, 8, 9, 10)
      output = '{"e":121550820000,"m":"m1","t":["t.a:value","t.b:v2"],"v":100}'
      expect do
        DDLambda.metric('m1', 100, time: now, "t.a": 'value', "t.b": 'v2')
      end.to output("#{output}\n").to_stdout
    end
  end
end

# rubocop:enable Metrics/BlockLength
