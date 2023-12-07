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

      IDEMPOTENT_COMMANDS = [
        "exists",
        "expire",
        "get",
        "getex",
        "getrange",
        "mget",
        "mset",
        "ping",
        "scard",
        "sdiff",
        "sdiffstore",
        "set",
        "sismember",
        "smembers",
        "smismember",
      ].freeze

      refine ::Redis::Client do
        private

        def with_resilience(action, destination, idempotent, &block)
          timeout_key = action == :connect ? :connect_timeout : :read_timeout
          original_timeout = @options[timeout_key]

          timeouts = NetworkResiliency.timeouts_for(
            adapter: :redis,
            action: action,
            destination: destination,
            max: @options[timeout_key],
            units: :seconds,
          )

          unless idempotent
            # only try once, with most lenient timeout
            timeouts = timeouts.last(1)
          end

          attempts = 0
          ts = -NetworkResiliency.timestamp

          begin
            attempts += 1
            error = nil

            @options[timeout_key] = timeouts.shift

            without_reconnect { yield }
          rescue ::Redis::BaseConnectionError, SystemCallError => e
            # capture error

            # grab underlying exception within Redis wrapper
            error = if e.is_a?(::Redis::BaseConnectionError)
              e.cause.class
            else
              e.class
            end

            retry if timeouts.size > 0

            raise
          ensure
            ts += NetworkResiliency.timestamp
            @options[timeout_key] = original_timeout

            NetworkResiliency.record(
              adapter: :redis,
              action: action,
              destination: destination,
              duration: ts,
              error: error,
              timeout: @options[timeout_key].to_f * 1_000,
              attempts: attempts,
            )
          end
        end

        def idempotent?(command)
          NetworkResiliency::Adapter::Redis::IDEMPOTENT_COMMANDS.include?(command)
        end
      end

      module Instrumentation
        using NetworkResiliency::Refinements
        using NetworkResiliency::Adapter::Redis

        def establish_connection
          return super unless NetworkResiliency.enabled?(:redis)

          with_resilience(:connect, host, true) { super }
        end

        def call(command)
          return super unless NetworkResiliency.enabled?(:redis)
          return super unless command.is_a?(Array)

          command_key = command.first.to_s

          # larger commands may have larger timeouts
          command_size = command.size.order_of_magnitude
          destination = [
            host,
            command_key,
            (command_size if command_size > 1),
          ].compact.join(":")

          idempotent = idempotent?(command_key)

          with_resilience(:request, destination, idempotent) { super }
        end
      end
    end
  end
end

