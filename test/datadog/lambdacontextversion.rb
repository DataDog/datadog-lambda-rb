# frozen_string_literal: true

# This is an example of the lambda context provided to a Ruby-runtimed lambda
# c.f. https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
# Use dot-notation to access these properties
class LambdaContextVersion
  def function_name
    'Ruby-test'
  end

  def function_version
    1
  end

  def invoked_function_arn
    'arn:aws:lambda:us-east-1:172597598159:function:ruby-test:1'
  end

  def memory_limit_in_mb
    128
  end

  def aws_request_id
    'dcbfed85-c904-4367-bd54-984ca201ef47'
  end

  def log_group_name
    "/aws/lambda/hello-dog-ruby-dev-helloRuby#{RUBY_VERSION[0, 3].tr('.', '')}"
  end

  def log_stream_name
    '2020/01/23/[$LATEST]996801b3ee1a4ebd8ec6ede5cc360bc7'
  end

  def deadline_ms
    1_579_818_015_751
  end

  def identity
    ''
  end

  def client_context
    ''
  end
end
