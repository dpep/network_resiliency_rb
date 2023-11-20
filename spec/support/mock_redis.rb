require "redis"
require "socket"

module Helpers
  module MockRedis
    def mock_redis(options)
      host = options[:host]

      raise Redis::TimeoutError if host =~ /timeout/

      client_socket, server_socket = Socket.pair(:UNIX, :STREAM, 0)

      Thread.new do
        line = server_socket.gets
        argv = Array.new(line[1..-3].to_i) do
          bytes = server_socket.gets[1..-3].to_i
          arg = server_socket.read(bytes)
          server_socket.read(2) # Discard \r\n
          arg
        end
        command = argv.shift

        if command == "ping"
          resp = "PONG"
          resp = "$%d\r\n%s\r\n" % [resp.length, resp]
        else
          # will raise Redis::CommandError
          resp = "-NOT IMPLEMENTED"
        end

        # server_socket.write("$%d\r\n%s\r\n" % [resp.length, resp])

        server_socket.write("#{resp}")
        server_socket.write("\r\n") unless resp.end_with?("\r\n")
        server_socket.close
      rescue Errno::EPIPE, Errno::ENOTCONN
      end

      Redis::Connection::Ruby.new(client_socket)
    end
  end
end


RSpec.configure do |config|
  config.include Helpers::MockRedis, :mock_redis

  config.before(mock_redis: true) do
    allow(Redis::Connection::Ruby).to receive(:connect, &method(:mock_redis))
  end
end
