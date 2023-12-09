gem "rails", ">= 5"
require "rails"

module NetworkResiliency
  module Adapter
    module Rails
      extend self

      def patch(instance = nil)
        instance ||= ::Rails.application

        unless instance.is_a?(::Rails::Application)
          raise ArgumentError, "expected Rails::Application instance, found: #{instance}"
        end

        return if patched?(instance)

        instance.config.middleware.use Middleware
      end

      def patched?(instance = nil)
        instance ||= ::Rails.application

        return false unless instance.initialized?

        instance.config.middleware.include?(Middleware)
      end

      class Middleware
        def initialize(app)
          @app = app
        end

        def call(env)
          header = HTTP::REQUEST_TIMEOUT_HEADER.upcase.tr('-', '_')
          timeout = env["HTTP_#{header}"]&.to_f

          NetworkResiliency.deadline = timeout if timeout

          @app.call(env)
        ensure
          NetworkResiliency.deadline = nil
        end
      end
    end
  end
end

