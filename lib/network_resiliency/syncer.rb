module NetworkResiliency
  class Syncer < Thread
    class << self
      def start(redis)
        NetworkResiliency.statsd&.increment("network_resiliency.syncer.start")

        stop if @instance
        @instance = new(redis)
      end

      def stop
        NetworkResiliency.statsd&.increment("network_resiliency.syncer.stop")

        if @instance
          @instance.shutdown
          @instance.join
          @instance = nil
        end
      end

      def syncing?
        !!@instance&.alive?
      end
    end

    def initialize(redis)
      @redis = redis

      super { sync }
    end

    def shutdown
      @shutdown = true

      # prevent needless delay
      self.raise Interrupt if status == "sleep"
    end

    private

    def sync
      until @shutdown
        NetworkResiliency.statsd&.increment("network_resiliency.syncer.sync")

        StatsEngine.sync(@redis)

        sleep(3)
      end
    rescue Interrupt
    end
  end
end
