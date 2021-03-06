require 'spec_helper'
require 'rspec/webservice_matchers'

describe '#up?' do
  it 'follows redirects when necessary' do
    RSpec::WebserviceMatchers.up?('perm-redirector.com').should be_true
    RSpec::WebserviceMatchers.up?('temp-redirector.org').should be_true
  end

  it 'retries timeout errors once' do
    RSpec::WebserviceMatchers.up?('http://www.timeout-once.com').should be_true
  end
end