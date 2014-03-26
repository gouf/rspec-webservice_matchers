require 'spec_helper'
require 'rspec/webservice_matchers'

describe 'json schema validation' do
  let(:missing_schema) { nil }
  let(:invalid_schema) { 'Definitely not a valid schema' }
  # let (:valid_schema) {  }

  it 'fails if schema data is not readable' do
    schema = missing_schema
    url    = 'http://www.website.com'

    expect {
      expect(url).to validate_against_json_schema(schema)
    }.to raise_exception RSpec::WebserviceMatchers::JsonSchemaUnreadable
  end

  it 'succeeds if the resource validates against the schema'
  it 'fails if the schema is not valid'
  it 'fails if the resource cannot be read'
  it "fails if resource doesn't validate against the schema"
end
