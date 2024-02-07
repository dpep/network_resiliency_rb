module NetworkResiliency
  class Syncer < Thread
    class << self
      def start
        NetworkResiliency.statsd&.increment("network_resiliency.syncer.start")

        stop if @instance
        @instance = new
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

    def initialize
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

        StatsEngine.sync(NetworkResiliency.redis)

        sleep(3)
      end
    rescue Interrupt
    end
  end
end
