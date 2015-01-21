require 'rspec/webservice_matchers/version'
require 'excon'
require 'faraday'
require 'faraday_middleware'
require 'pry'

# Seconds
TIMEOUT = 20
OPEN_TIMEOUT = 20

module RSpec
  # RSpec Custom Matchers
  # See https://www.relishapp.com/rspec/rspec-expectations/v/2-3/docs/custom-matchers/define-matcher
  module WebserviceMatchers
    # Test whether https is correctly implemented
    RSpec::Matchers.define :have_a_valid_cert do
      error_message = nil

      match do |domain_name_or_url|
        begin
          WebserviceMatchers.try_ssl_connection(domain_name_or_url)
          true
        rescue Exception => e
          error_message = e.message
          false
        end
      end

      failure_message_for_should do
        error_message
      end
    end

    # Pass successfully if we get a 301 to the place we intend.
    RSpec::Matchers.define :redirect_permanently_to do |expected|
      state = {}
      error_message   = nil
      actual_status   = nil
      actual_location = nil

      match do |url_or_domain_name|
        begin
          response = WebserviceMatchers.make_response(url_or_domain_name)
          expected = WebserviceMatchers.make_url(expected)
          actual_location = response.headers['location']
          actual_status   = response.status

          regex = /#{expected}\/?/
          expected_status   = actual_status.eql?(301)
          expected_location = regex.match(actual_location)
          expected_status && expected_location
        rescue Exception => e
          error_message = e.message
          false
        end
      end

      failure_message_for_should do
        if !error_message.nil?
          error_message
        else
          mesgs = []
          if [302, 307].include? actual_status
            mesgs << "received a temporary redirect, status #{actual_status}"
          end
          unless actual_location.nil? && (/#{expected}\/?/.eql? actual_location)
            mesgs << "received location #{actual_location}"
          end
          mesgs << WebserviceMatchers.redirected?
          mesgs.join('; ').capitalize
        end
      end
    end

    # Pass successfully if we get a 302 or 307 to the place we intend.
    RSpec::Matchers.define :redirect_temporarily_to do |expected|
      include RSpec
      error_message = nil
      actual_status = nil
      actual_location = nil

      match do |url_or_domain_name|
        begin
          response = WebserviceMatchers.recheck_on_timeout { WebserviceMatchers.connection.head(WebserviceMatchers.make_url url_or_domain_name) }
          expected = WebserviceMatchers.make_url(expected)
          actual_location = response.headers['location']
          actual_status   = response.status

          [302, 307].include?(actual_status) && (/#{expected}\/?/ =~ actual_location)
        rescue Exception => e
          error_message = e.message
          false
        end
      end

      failure_message_for_should do
        if !error_message.nil?
          error_message
        else
          mesgs = []
          webm = WebserviceMatchers
          mesgs << webm.received_permanent_redirect(actual_status)
          mesgs << webm.received_location(expected, actual_location)
          mesgs << webm.redirected(actual_status)
          mesgs.join('; ').capitalize
        end
      end
    end

    # This is a high level matcher which checks three things:
    # 1. Permanent redirect
    # 2. to an https url
    # 3. which is correctly configured
    RSpec::Matchers.define :enforce_https_everywhere do
      error_msg         = nil
      actual_status     = nil
      actual_protocol   = nil
      actual_valid_cert = nil

      match do |domain_name|
        begin
          webm = WebserviceMatchers
          response = webm.make_response("http://#{domain_name}")
          new_url  = response.headers['location']
          actual_status  = response.status
          /^(?<protocol>https?)/ =~ new_url
          actual_protocol = protocol unless protocol.nil?
          actual_valid_cert = webm.valid_ssl_cert?(new_url)
          args = [actual_status, actual_protocol, actual_valid_cert]
          redirected_on_valid_ssl?(args)
        rescue Faraday::Error::ConnectionFailed
          error_msg = 'Connection failed'
          false
        end
      end

      # Create a compound error message listing all of the
      # relevant actual values received.
      failure_message_for_should do
        if error_msg.nil?
          mesgs = []
          webm = WebserviceMatchers
          mesgs << webm.received_permanent_redirect(actual_status)
          mesgs << webm.destination_protocol(actual_protocol)
          mesgs << "there's no valid SSL certificate" unless actual_valid_cert
          mesgs.join('; ').capitalize
        else
          error_msg
        end
      end
    end

    # Pass when a URL returns the expected status code
    # Codes are defined in http://www.rfc-editor.org/rfc/rfc2616.txt
    RSpec::Matchers.define :be_status do |expected_code|
      actual_code = nil

      match do |url_or_domain_name|
        url           = WebserviceMatchers.make_url(url_or_domain_name)
        response      = WebserviceMatchers.make_response(url)
        actual_code   = response.status
        expected_code = expected_code.to_i

        actual_code == expected_code
      end

      failure_message_for_should do
        "Received status #{actual_code}"
      end
    end

    # Pass when the response code is 200, following redirects
    # if necessary.
    RSpec::Matchers.define :be_up do
      actual_status = nil

      match do |url_or_domain_name|
        url  = WebserviceMatchers.make_url(url_or_domain_name)
        conn = WebserviceMatchers.connection(follow: true)
        response = WebserviceMatchers.recheck_on_timeout { conn.head(url) }
        actual_status = response.status
        actual_status == 200
      end

      failure_message_for_should do
        "Received status #{actual_status}"
      end
    end

    # Return true if the given page has status 200,
    # and follow a few redirects if necessary.
    def self.up?(url_or_domain_name)
      url  = make_url(url_or_domain_name)
      conn = connection(follow: true)
      response = recheck_on_timeout { conn.head(url) }
      response.status == 200
    end

    def self.valid_ssl_cert?(domain_name_or_url)
      try_ssl_connection(domain_name_or_url)
      true
    rescue
      # Not serving SSL, expired, or incorrect domain name in certificate
      false
    end

    def self.try_ssl_connection(domain_name_or_url)
      url = "https://#{remove_protocol(domain_name_or_url)}"
      recheck_on_timeout { connection.head(url) }
    end


    private

    def self.connection(follow: false)
      Faraday.new do |c|
        c.options[:timeout] = TIMEOUT
        c.options[:open_timeout] = OPEN_TIMEOUT
        c.use(FaradayMiddleware::FollowRedirects, limit: 4) if follow
        c.adapter :excon
      end
    end

    # Ensure that the given string is a URL,
    # making it into one if necessary.
    def self.make_url(url_or_domain_name)
      if %r{^https?://} =~ url_or_domain_name
        url_or_domain_name
      else
        "http://#{url_or_domain_name}"
      end
    end

    # Normalize the input: remove 'http(s)://' if it's there
    def self.remove_protocol(domain_name_or_url)
      %r{^https?://(?<name>.+)$} =~ domain_name_or_url
      name || domain_name_or_url
    end

    def self.recheck_on_timeout
      yield
    rescue Faraday::Error::TimeoutError
      yield
    end

    def self.make_response(url_or_domain_name)
      connection = lambda do
        webm = WebserviceMatchers
        url = webm.make_url(url_or_domain_name)
        webm.connection.head(url)
      end
      webm.recheck_on_timeout { connection.call }
    end

    def self.redirected(actual_status)
      message = "not a redirect: received status #{actual_status}"
      [301, 302, 307].include?(actual_status) ? '' : message
    end

    def self.received_location(expected, actual_location)
      message = "received location #{actual_location}"
      condition = actual_location.nil? && (/#{expected}\/?/ == actual_location)
      condition ? '' : message
    end

    def self.received_permanent_redirect(actual_status)
      message = "received a permanent redirect, status #{actual_status}"
      (actual_status == 301) ? message : ''
    end

    def self.destination_protocol(actual_protocol)
      return '' if actual_protocol.nil?
      message = "destination uses protocol #{actual_protocol.upcase}"
      actual_protocol == 'https' ? message : ''
    end

    def self.redirected_on_valid_ssl?(args)
      actual_status, actual_protocol, actual_valid_cert = args
      (actual_status == 301) &&
        (actual_protocol == 'https') &&
        (actual_valid_cert == true)
    end
  end
end
