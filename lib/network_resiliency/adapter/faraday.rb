require "faraday"

module NetworkResiliency
  module Adapter
    class Faraday < ::Faraday::Middleware

      def self.patched?(conn)
        conn.builder.handlers.include?(self)
      end

      def call(env)
        return super unless NetworkResiliency.enabled?(:faraday)

        NetworkResiliency.disable! { _call(env) }
      end

      private

      def _call(env)
# env.options.timeout = 0.001
# open_timeout

        # url => id
        # predict time
        # get dynamic timeout

        # temp update timeout
        # with_timeout(...) { super }

        ts = -NetworkResiliency.timestamp

        # super
        app.call(env)
      rescue ::Faraday::ConnectionFailed, ::Faraday::TimeoutError => e
        # capture error
        raise
      ensure
        ts += NetworkResiliency.timestamp

        NetworkResiliency.statsd&.distribution(
          "network_resiliency.connect",
          ts,
          tags: {
            adapter: "faraday",
            destination: env.url.host,
            error: e&.wrapped_exception.class,
            # timeout: env.options.open_timeout || env.options.timeout,
          }.compact,
        )
      end

      # def normalized_id(env)
      #   env.url
      # end

      # def with_timeout(env, timeout)
      #   old_timeouts = [
      #     env.options.timeout,
      #     env.options.open_timeout,
      #     env.options.read_timeout,
      #     env.options.write_timeout,
      #   ]

      #   env.options.timeout = [
      #     env.options.timeout,
      #     timeout,
      #   ].compact.min

      #   # env.options.open_timeout = [ env.options.open_timeout, timeout ].compact.min
      #   # ...
      # ensure
      #   env.options.timeout = old_timeouts[0]
      #   # ...
      # end
    end
  end
end

Faraday::Request.register_middleware(
  network_resiliency: NetworkResiliency::Adapter::Faraday,
)

# https://github.com/lostisland/faraday_middleware/blob/main/lib/faraday_middleware.rb
