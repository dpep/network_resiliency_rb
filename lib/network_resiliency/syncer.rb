module NetworkResiliency
  class Syncer < Thread
    LOCK = Mutex.new

    class << self
      def start
        return unless NetworkResiliency.redis

        LOCK.synchronize do
          unless @instance&.alive?
            @instance = new
            NetworkResiliency.statsd&.increment("network_resiliency.syncer.start")
          end

          @instance
        end
      end

      def stop
        LOCK.synchronize do
          if @instance
            @instance.shutdown
            @instance.join
            @instance = nil
          end
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
        StatsEngine.sync(NetworkResiliency.redis)

        sleep(10)
      end
    rescue Interrupt
    rescue => e
      NetworkResiliency.warn(__method__, e)
    end
  end
end
