# require "socket"

module Helpers
  module MockServer
    def mock_server
      client_socket, server_socket = Socket.pair(:UNIX, :STREAM, 0)

      allow(client_socket).to receive(:setsockopt)

      Thread.new do
        verb, path, _ = server_socket.gets.split
        while line = server_socket.gets and line !~ /^\s*$/
          # puts "client: #{line}"
        end

        resp = "OK"
        headers = [
          "http/1.1 200 ok",
          # "content-type: text/html; charset=iso-8859-1",
          "content-length: #{resp.length}\r\n\r\n",
        ]
        server_socket.puts headers.join("\r\n")
        server_socket.puts resp
        server_socket.close
      end

      client_socket
    end
  end
end


RSpec.configure do |config|
  config.include Helpers::MockServer

  config.before do
    allow(Socket).to receive(:tcp) do |host, *args|
      raise Net::OpenTimeout if host =~ /timeout/

      mock_server
    end

    # allow(TCPSocket).to receive(:open).and_wrap_original do |original_method, *args|
    #   client_socket
    # end
  end
end
