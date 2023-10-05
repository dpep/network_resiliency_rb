gem "pg", "~> 1.1"
require "pg"

module NetworkResiliency
  module Adapter
    module Postgres
      extend self

      def patch
        return if patched?

        PG::Connection.singleton_class.prepend(Instrumentation)
      end

      def patched?
        PG::Connection.singleton_class.ancestors.include?(Instrumentation)
      end

      module Instrumentation
        def connect_start(opts)
          host = opts[:host].split(",")[0] if opts[:host]

          return super unless NetworkResiliency.enabled?(:postgres)

          begin
            ts = -NetworkResiliency.timestamp

            super
          rescue PG::Error => e
            # capture error
            raise
          ensure
            ts += NetworkResiliency.timestamp

            NetworkResiliency.record(
              adapter: "postgres",
              action: "connect",
              destination: host,
              error: e&.class,
              duration: ts,
            )
          end
        end
      end
    end
  end
end
