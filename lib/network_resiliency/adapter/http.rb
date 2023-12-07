require "net/http"

module NetworkResiliency
  module Adapter
    module HTTP
      extend self

      REQUEST_TIMEOUT_HEADER = "X-Request-Timeout"

      def patch(instance = nil)
        return if patched?(instance)

        (instance&.singleton_class || Net::HTTP).prepend(Instrumentation)
      end

      def patched?(instance = nil)
        (instance&.singleton_class || Net::HTTP).ancestors.include?(Instrumentation)
      end

      ID_REGEX = %r{/[0-9]+(?=/|$)}.freeze
      UUID_REGEX = %r`/\h{8}-\h{4}-(\h{4})-\h{4}-\h{12}(?=/|$)`.freeze

      refine Net::HTTP do
        def normalize_path(path)
          NetworkResiliency.normalize_request(:http, path, host: address).gsub(
            Regexp.union(
              NetworkResiliency::Adapter::HTTP::ID_REGEX,
              NetworkResiliency::Adapter::HTTP::UUID_REGEX,
            ),
            '/x',
          ).gsub(%r{//+}, "/")
        end

        def with_resilience(action, destination, idempotent, &block)
          if action == :connect
            original_timeout = self.open_timeout
            set_timeout = ->(timeout) { self.open_timeout = timeout }
          else
            original_timeout = self.read_timeout
            set_timeout = ->(timeout) { self.read_timeout = timeout }
          end

          timeouts = NetworkResiliency.timeouts_for(
            adapter: "http",
            action: action.to_s,
            destination: destination,
            max: original_timeout,
            units: :seconds,
          )

          unless idempotent
            # only try once, with most lenient timeout
            timeouts = timeouts.last(1)
          end

          original_max_retries = self.max_retries
          self.max_retries = 0 # disable

          attempts = 0
          ts = -NetworkResiliency.timestamp

          begin
            attempts += 1
            error = nil

            timeout = timeouts.shift
            set_timeout.call(timeout)

            yield timeout
          rescue ::Timeout::Error,
             defined?(OpenSSL::SSL) ? OpenSSL::OpenSSLError : IOError,
             SystemCallError => e

            # capture error
            error = e.class

            retry if timeouts.size > 0

            raise
          ensure
            ts += NetworkResiliency.timestamp
            set_timeout.call(original_timeout)
            self.max_retries = original_max_retries

            NetworkResiliency.record(
              adapter: "http",
              action: action.to_s,
              destination: destination,
              duration: ts,
              error: error,
              timeout: original_timeout.to_f * 1_000,
              attempts: attempts,
            )
          end
        end
      end

      module Instrumentation
        using NetworkResiliency::Adapter::HTTP

        def connect
          return super unless NetworkResiliency.enabled?(:http)

          with_resilience(:connect, address, true) { super }
        end

        def transport_request(req, &block)
          return super unless NetworkResiliency.enabled?(:http)

          # strip query params
          path = URI.parse(req.path).path

          destination = [
            address,
            req.method.downcase,
            normalize_path(path),
          ].join(":")

          idepotent = Net::HTTP::IDEMPOTENT_METHODS_.include?(req.method)

          with_resilience(:request, destination, idepotent) do |timeout|
            # send timeout via headers
            req[REQUEST_TIMEOUT_HEADER] = timeout

            super
          end
        end
      end
    end
  end
end
