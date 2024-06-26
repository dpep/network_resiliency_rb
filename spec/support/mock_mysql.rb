require "mysql2"
require "socket"

module Helpers
  module MockMysql
    SOCKET_PATH = "/tmp/mock_mysql.sock"

    def mock_mysql
      # raise Mysql2::Error::TimeoutError.new("fake timeout", nil, error_number = 1205)

      File.delete(SOCKET_PATH) if File.exist?(SOCKET_PATH)

      server = UNIXServer.new(SOCKET_PATH)

      Thread.new do
        socket, _ = server.accept

        # line = socket.recv(1024)
        # line = socket.gets.chomp
        # puts "mysql server: #{line}"

        # server_socket.write("#{resp}")
        # server_socket.write("\r\n") unless resp.end_with?("\r\n")
      ensure
        socket&.close
      end

      SOCKET_PATH
    end
  end
end


RSpec.configure do |config|
  config.include Helpers::MockMysql, :mock_mysql

  config.after(mock_mysql: true) do
    # clean up socket file
    File.delete(Helpers::MockMysql::SOCKET_PATH) if File.exist?(Helpers::MockMysql::SOCKET_PATH)
  end
end
