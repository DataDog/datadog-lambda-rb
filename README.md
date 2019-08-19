# Example Usage

```ruby
require 'ddlambda'
require 'json'

def handler(event:, context:)
    DDLambda.wrap(event, context) do
        # Implement your logic here
        return { statusCode: 200, body: JSON.generate('Hello World') }
    end
end
```
