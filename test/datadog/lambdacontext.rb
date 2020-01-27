# frozen_string_literal: true

# This is an example of the lambda context provided to a Ruby-runtimed lambda
# c.f. https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
# Use dot-notation to access these properties
class LambdaContext
  def function_name
    'hello-dog-ruby-dev-helloRuby25'
  end

  def function_version
    '$LATEST'
  end

  def invoked_function_arn
    'arn:aws:lambda:us-east-1:172597598159:function:hello-dog-ruby-dev-hello'
  end

  def memory_limit_in_mb
    128
  end

  def aws_request_id
    'dcbfed85-c904-4367-bd54-984ca201ef47'
  end

  def log_group_name
    '/aws/lambda/hello-dog-ruby-dev-helloRuby25'
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
