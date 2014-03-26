require 'spec_helper'
require 'rspec/webservice_matchers'

describe 'json schema validation' do
  let(:valid_resource) { 'https://www.eff.org/' }
  let(:missing_schema) { nil }
  let(:invalid_schema) { 'Definitely not a valid schema' }
  # let (:valid_schema) {  }

  it 'fails if schema data not readable' do
    expect {
      valid_resource.should be_valid_json(missing_schema)
    }.to raise_exception RSpec::WebserviceMatchers::JsonSchemaUnreadable
  end

  it 'succeeds if the resource validates against the schema'
  it 'fails if the schema is not valid'
  it 'fails if the resource cannot be read'
  it "fails if resource doesn't validate against the schema"
end
