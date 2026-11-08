# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module NotifyKit
  module Transports
    # Minimal HTTP client on stdlib net/http (no runtime dependency).
    #
    # Its key job is classifying network failures by whether the request could
    # have reached the server:
    #   - connect refused / DNS / open timeout  => TransientFailure (never sent, safe to retry)
    #   - read/write timeout, reset, EOF        => UnknownOutcome   (may have been processed)
    class NetHttp
      Response = Data.define(:status, :headers, :body, :json)

      NOT_SENT = [Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout,
                  SocketError].freeze
      MAYBE_SENT = [Net::ReadTimeout, Net::WriteTimeout, EOFError, Errno::ECONNRESET, Errno::EPIPE,
                    IOError].freeze

      def initialize(open_timeout: 3, read_timeout: 10, write_timeout: 10)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @write_timeout = write_timeout
      end

      # @param json [Hash, nil] JSON body
      # @param form [Hash, nil] application/x-www-form-urlencoded body
      def post(url, headers: {}, json: nil, form: nil)
        uri = URI(url)
        request = Net::HTTP::Post.new(uri, headers)
        if json
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(json)
        elsif form
          request.set_form_data(form)
        end
        perform(uri, request)
      end

      private

      def perform(uri, request)
        response = connection(uri).start { |http| http.request(request) }
        Response.new(status: response.code.to_i, headers: response.to_hash, body: response.body,
                     json: parse(response.body))
      rescue *NOT_SENT => e
        raise TransientFailure, "#{uri.host}: #{e.class} (request not sent)"
      rescue *MAYBE_SENT => e
        raise UnknownOutcome, "#{uri.host}: #{e.class} after request was sent"
      end

      def connection(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        http.write_timeout = @write_timeout
        # net/http silently retries idempotent requests once; make sure it never
        # resends anything on our behalf.
        http.max_retries = 0
        http
      end

      def parse(body)
        body.nil? || body.empty? ? nil : JSON.parse(body)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
