require "redis"

module NetworkResiliency
  module Adapter
    module Redis
      extend self

      def patch(instance = nil)
        return if patched?(instance)

        if instance
          unless instance.is_a?(::Redis)
            raise ArgumentError, "expected Redis instance, found: #{instance}"
          end

          client = instance.instance_variable_get(:@client)

          unless client.is_a?(::Redis::Client)
            raise ArgumentError, "unsupported Redis client: #{client}"
          end

          client.singleton_class.prepend(Instrumentation)
        else
          ::Redis::Client.prepend(Instrumentation)
        end
      end

      def patched?(instance = nil)
        if instance
          client = instance.instance_variable_get(:@client)

          client && client.singleton_class.ancestors.include?(Instrumentation)
        else
          ::Redis::Client.ancestors.include?(Instrumentation)
        end
      end

      module Instrumentation
        def establish_connection
          return super unless NetworkResiliency.enabled?(:redis)

          original_timeout = @options[:connect_timeout]

          timeouts = NetworkResiliency.timeouts_for(
            adapter: "redis",
            action: "connect",
            destination: host,
            max: original_timeout,
          )

          attempts = 0
          ts = -NetworkResiliency.timestamp

          begin
            attempts += 1
            error = nil

            @options[:connect_timeout] = timeouts.shift

            super
          rescue ::Redis::CannotConnectError => e
            # capture error

            # grab underlying exception within Redis wrapper
            error = e.cause.class

            retry if timeouts.size > 0

            raise
          ensure
            ts += NetworkResiliency.timestamp
            @options[:connect_timeout] = original_timeout

            NetworkResiliency.record(
              adapter: "redis",
              action: "connect",
              destination: host,
              duration: ts,
              error: error,
              timeout: @options[:connect_timeout],
              attempts: attempts,
            )
          end
        end
      end
    end
  end
end

