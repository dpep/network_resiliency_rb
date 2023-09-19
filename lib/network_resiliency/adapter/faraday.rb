require "faraday"

module NetworkResiliency
  module Adapter
    class Faraday < ::Faraday::Middleware
      def call(env)
        puts "NetworkResiliency called: #{env.url}"
# env.options.timeout = 0.001
# open_timeout

        # url => id
        # predict time
        # get dynamic timeout

        if NetworkResiliency.enabled?
          # temp update timeout
          # with_timeout(...) { super }
        else
          super
        end
      rescue ::Faraday::Error => e
        # note exception for ensure block
      ensure
        # record time taken

        # reraise if applicable
        raise e if e
      end

      def normalized_id(env)
        env.url
      end

      def with_timeout(env, timeout)
        old_timeouts = [
          env.options.timeout,
          env.options.open_timeout,
          env.options.read_timeout,
          env.options.write_timeout,
        ]

        env.options.timeout = [
          env.options.timeout,
          timeout,
        ].compact.min

        # env.options.open_timeout = [ env.options.open_timeout, timeout ].compact.min
        # ...
      ensure
        env.options.timeout = old_timeouts[0]
        # ...
      end
    end
  end
end

Faraday::Request.register_middleware(
  network_resiliency: NetworkResiliency::Adapter::Faraday,
)

# https://github.com/lostisland/faraday_middleware/blob/main/lib/faraday_middleware.rb
