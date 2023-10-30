module NetworkResiliency
  module StatsEngine
    extend self

    LOCK = Thread::Mutex.new
    STATS = {}

    def add(key, value)
      local, _ = synchronize do
        STATS[key] ||= [ Stats.new, Stats.new ]
      end

      local << value
    end

    def get(key)
      local, remote = synchronize { STATS[key] }

      local && remote ? (local + remote) : Stats.new
    end

    def reset
      synchronize { STATS.clear }
    end

    def sync(redis, keys)
      data = synchronize do
        keys.map do |key|
          local, remote = STATS[key]
          next unless local && remote
          next unless local.n > 0

          remote << local
          STATS[key] = [ Stats.new, remote ]

          [ key, local ]
        end.compact.to_h
      end

      # sync data to redis
      remote_stats = Stats.sync(redis, **data)

      # integrate remote results
      synchronize do
        remote_stats.each do |key, stats|
          local, remote = STATS[key]
          STATS[key] = [ local, stats ]
        end
      end

      remote_stats.keys
    end

    private

    def synchronize
      LOCK.synchronize { yield }
    end
  end
end
