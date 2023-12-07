require "net/http"
require "socket"

module Helpers
  module MockServer
    def mock_server(host, *args)
      raise Net::OpenTimeout if host =~ /timeout/

      client_socket, server_socket = Socket.pair(:UNIX, :STREAM, 0)

      allow(client_socket).to receive(:setsockopt)

      Thread.new do
        verb, path, _ = server_socket.gets&.split
        request_headers = []
        while line = server_socket.gets and line !~ /^\s*$/
          # puts "client: #{line}"

          request_headers << line.strip if line.start_with?("X-")
        end

        sleep $1.to_f if path =~ %r{/timeout/(\d+)}

        resp = "OK"
        headers = [
          "HTTP/1.1 200 OK",
          # "content-type: text/html; charset=iso-8859-1",
          (request_headers.join("\r\n") unless request_headers.empty?),
          "content-length: #{resp.length}",
          "\r\n",
        ].compact

        server_socket.puts headers.join("\r\n")
        server_socket.puts resp
        server_socket.close
      rescue Errno::EPIPE
      end

      client_socket
    end
  end
end


RSpec.configure do |config|
  config.include Helpers::MockServer, :mock_socket

  config.before(mock_socket: true) do
    allow(Socket).to receive(:tcp, &method(:mock_server))
    allow(TCPSocket).to receive(:open, &method(:mock_server))
  end
end
