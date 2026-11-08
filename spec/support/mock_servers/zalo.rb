# frozen_string_literal: true

require "json"
require "webrick"

module MockServers
  # A real HTTP server (WEBrick on a random port) imitating the Zalo endpoints we
  # use, so timeouts, resets and status codes are exercised for real.
  #
  #   zalo = MockServers::Zalo.instance
  #   zalo.reset!
  #   zalo.enqueue(:rate_limited, :ok)   # behaviour of the next send requests
  #   zalo.sent                          # payloads Zalo "received" (physical deliveries)
  #   zalo.refresh_calls                 # how many times the refresh endpoint was hit
  #
  # Send modes: :ok, :rate_limited, :bad_gateway (502), :server_error (500),
  # :lost_response (records the message, then responds slower than the client timeout),
  # [:error, code] (HTTP 200 with a Zalo error code).
  class Zalo
    SLOW_RESPONSE_SECONDS = 1.5

    def self.instance
      @instance ||= new
    end

    attr_reader :port

    def initialize
      @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1",
                                        Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      @port = @server.config[:Port]
      @mutex = Mutex.new
      reset!
      mount
      Thread.new { @server.start }
    end

    def url = "http://127.0.0.1:#{port}"
    def urls = { oauth: url, business: url, openapi: url }

    def reset!(access_token: "access-1", refresh_token: "refresh-1", refresh_delay: 0)
      @mutex.synchronize do
        @modes = []
        @sent = []
        @refresh_calls = 0
        @access_token = access_token
        @refresh_token = refresh_token
        @refresh_delay = refresh_delay
        @generation = 1
      end
    end

    def enqueue(*modes) = @mutex.synchronize { @modes.concat(modes) }
    def sent = @mutex.synchronize { @sent.dup }
    def refresh_calls = @mutex.synchronize { @refresh_calls }
    def current_tokens = @mutex.synchronize { [@access_token, @refresh_token] }

    # Simulate Zalo expiring the current access token server-side.
    def expire_access_token! = @mutex.synchronize { @access_token = "server-rotated-#{rand(1_000_000)}" }

    private

    def mount
      @server.mount_proc("/message/template") { |req, res| handle_send(req, res, :zns) }
      @server.mount_proc("/v3.0/oa/message/cs") { |req, res| handle_send(req, res, :oa) }
      @server.mount_proc("/v4/oa/access_token") { |req, res| handle_refresh(req, res) }
    end

    def handle_send(req, res, kind)
      payload = JSON.parse(req.body)
      mode = @mutex.synchronize { req["access_token"] == @access_token ? (@modes.shift || :ok) : nil }
      return json(res, { error: -220, message: "Access token is expired or removed" }) unless mode

      respond_send(res, mode, kind, payload)
    end

    def respond_send(res, mode, kind, payload)
      case mode
      when :ok then accept(res, kind, payload)
      when :rate_limited
        res.status = 429
        res["Retry-After"] = "7"
        json(res, { error: -32, message: "rate limited" }, status: 429)
      when :bad_gateway then json(res, { message: "bad gateway" }, status: 502)
      when :server_error then json(res, { message: "internal error" }, status: 500)
      when :lost_response
        record(kind, payload)
        sleep SLOW_RESPONSE_SECONDS
        json(res, { error: 0, data: { msg_id: "late" } })
      when Array then json(res, { error: mode.last, message: "mock error #{mode.last}" })
      end
    end

    def accept(res, kind, payload)
      id = record(kind, payload)
      data = if kind == :zns
               { msg_id: "zmsg-#{id}",
                 quota: { dailyQuota: "500", remainingQuota: "499" } }
             else
               { message_id: "oamsg-#{id}" }
             end
      json(res, { error: 0, message: "Success", data: data })
    end

    def record(kind, payload)
      @mutex.synchronize do
        @sent << payload.merge("_kind" => kind.to_s)
        @sent.size
      end
    end

    def handle_refresh(req, res)
      given = req.query["refresh_token"]
      sleep @refresh_delay if @refresh_delay.positive?
      body = @mutex.synchronize do
        @refresh_calls += 1
        next { error: -14_014, error_name: "Invalid refresh token" } unless given == @refresh_token

        # Single-use: the old refresh token dies with this call.
        @generation += 1
        @access_token = "access-#{@generation}"
        @refresh_token = "refresh-#{@generation}"
        { access_token: @access_token, refresh_token: @refresh_token, expires_in: "90000" }
      end
      json(res, body)
    end

    def json(res, body, status: 200)
      res.status = status
      res["Content-Type"] = "application/json"
      res.body = JSON.generate(body)
    end
  end
end
