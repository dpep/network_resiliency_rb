module NetworkResiliency
  class Syncer < Thread
    class << self
      def start(redis)
        @instance&.shutdown
        @instance = new(redis)
      end

      def stop
        @instance&.shutdown
        @instance = nil
      end
    end

    def initialize(redis)
      @redis = redis

      super { sync }
    end

    def shutdown
      @shutdown = true

      # prevent needless delay
      raise Interrupt if status == "sleep"
    end

    private

    def sync
      until @shutdown
        StatsEngine.sync(@redis)

        sleep(3)
      end
    rescue Interrupt
    end
  end
end
