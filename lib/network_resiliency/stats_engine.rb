module NetworkResiliency
  module StatsEngine
    extend self

    LOCK = Thread::Mutex.new
    STATS = {}
    SYNC_LIMIT = 100

    def add(key, value)
      local, _ = synchronize do
        STATS[key] ||= [ Stats.new, Stats.new ]
      end

      local << value
    end

    def get(key)
      local, remote = synchronize do
        STATS[key] ||= [ Stats.new, Stats.new ]
      end

      local + remote
    end

    def reset
      synchronize { STATS.clear }
    end

    def sync(redis)
      dirty_keys = {}

      # select data to be synced
      data = synchronize do
        dirty_keys = STATS.map do |key, (local, remote)|
          # skip if no new local stats and remote already synced
          next if local.n == 0 && remote.n > 0

          [ key, local.n ]
        end.compact.to_h

        # select keys to sync, prioritizing most used
        keys = dirty_keys.sort_by do |key, weight|
          -weight
        end.take(SYNC_LIMIT).map(&:first)

        # update stats for keys being synced
        keys.map do |key|
          local, remote = STATS[key]

          remote << local # update remote stats until sync completes
          STATS[key][0] = Stats.new # reset local stats

          [ key, local ]
        end.to_h
      end

      NetworkResiliency.statsd&.distribution(
        "network_resiliency.sync.keys",
        data.size,
        tags: {
          empty: data.empty?,
          truncated: data.size < dirty_keys.size,
        }.select { |_, v| v },
      )

      NetworkResiliency.statsd&.distribution(
        "network_resiliency.sync.keys.dirty",
        dirty_keys.select { |_, n| n > 0 }.count,
      )

      return [] if data.empty?

      # sync data to redis
      remote_stats = if NetworkResiliency.statsd
        NetworkResiliency.statsd&.time("network_resiliency.sync") do
          Stats.sync(NetworkResiliency.redis, **data)
        end
      else
        Stats.sync(NetworkResiliency.redis, **data)
      end

      # integrate new remote stats
      synchronize do
        remote_stats.each do |key, stats|
          local, remote = STATS[key]

          remote.reset
          remote << stats
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
