require "redis"

module ApiAvenger
  module Adapter
    module Redis
      def connect(redis_config)
        puts "RedisClient.connect(#{client.connect_timeout})"

        old_timeout = client.connect_timeout

        already_connected = client.connected?

        # client.connect_timeout = 0.1
        ts = -ApiAvenger.timestamp
        super
      ensure
        client.connect_timeout = old_timeout

        ts += ApiAvenger.timestamp

        note = already_connected ? " (already_connected)" : ""

        puts "connect time: #{ts}#{note}"
      end

      def call(command, redis_config)
        puts "RedisClient.call"

        key = "#{id}:call"
        ts = -ApiAvenger.timestamp
        with_timeout(1) { super }
      ensure
        ts += ApiAvenger.timestamp
        puts "call time: #{ts}"

        ApiAvenger.record(self, id, ts)
      end

      def id
        "redis:#{client.host}"
      end

      def with_timeout(timeout)
        old_timeouts = [
          client.connect_timeout,
          client.read_timeout,
          client.write_timeout,
        ]

        client.connect_timeout = timeout
        client.read_timeout = timeout
        client.write_timeout = timeout

        yield
      ensure
        client.connect_timeout, client.read_timeout, client.write_timeout = *old_timeouts
      end
    end
  end
end

# RedisClient.register(RedisAvenger)
# Redis.new(middlewares: [RedisAvenger])
