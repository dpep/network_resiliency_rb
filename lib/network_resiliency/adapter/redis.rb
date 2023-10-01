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
        # def initialize(...)
        #   super

        #   @network_resiliency_attempts = options[:reconnect_attempts]
        #   options[:reconnect_attempts] = 0
        # end

        def establish_connection
          return super unless NetworkResiliency.enabled?(:redis)

          begin
            ts = -NetworkResiliency.timestamp

            super
          rescue ::Redis::CannotConnectError => e
            # capture error
            raise
          ensure
            ts += NetworkResiliency.timestamp

            # grab underlying exception within Redis wrapper
            error = e ? e.cause.class : nil

            NetworkResiliency.record(
              adapter: "redis",
              action: "connect",
              destination: host,
              error: error,
              duration: ts,
            )
          end
        end
      end
    end
  end
end

