require "api_avenger/stats"
require "api_avenger/version"

module ApiAvenger
  extend self

  def enabled?
    true
  end

  def sample?
    enabled? || rand < sample_rate
  end

  # def mode=(mode)
  #   unless [ :avg, :x10, :sig1, :sig2, :sig3 ]
  # end

  def timeout(adapter, key)
    stats = self.stats(adapter, key)

    stats.avg * 10 if stats.n >= 100
  end

  def stats(adapter, key)
    store.get(
      [
        adapter.class.to_s.split("::")[-1],
        key,
      ].join(":"),
    )
  end

  def record(adapter, key, milliseconds)
    compound_key = [
      adapter.class.to_s.split("::")[-1],
      key,
    ].join(":")

    # normalize timestamp
    milliseconds = [ milliseconds.round, 1 ].max

    store.record(compound_key, milliseconds)
  end

  def timestamp
    Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000
  end

  def time
    # if block_given?
    ts = -timestamp
    yield

    ts += timestamp
  end

  def store
    @store ||= MemoryStore.new
  end

  class Store
    def get(key)
      raise NotImplemented
    end

    def record(key, time)
      raise NotImplemented
    end

    def flush
      raise NotImplemented
    end
  end

  class MemoryStore < Store
    def initialize(substore = nil)
      @substore = substore
      @data = {}
    end

    def get(key)
      @data[key] ||= @substore&.get(key) || Stats.new
    end

    def record(key, time)
      get(key) << time
      @substore&.record(key, time)

      self
    end

    def flush
      @substore&.flush
    end
  end

  class RedisStore < Store
    def initialize(redis)
      @redis = redis
    end

    def cachekey(key)
      [ ApiAvenger, key ].join(":")
    end
  end
end


require "api_avenger/adapter/faraday"
require "api_avenger/adapter/redis"

# ms granularity, round up, floor(1)
#

# storage
# get(id) / record(id, time) / flush

# local storage
#  - get(id) / save(id, time)
# remote storage
#  - get(id) - sync
#  - save(id, time) - buffer and async flush
