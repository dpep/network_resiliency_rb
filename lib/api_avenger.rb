require "api_avenger/stats"
require "api_avenger/version"

module ApiAvenger
  extend self

  def defend(id)
    # look up stats for id
    # calculate and yield time limit
    # record actual time taken
  end

  def enabled?(...)
  end

  def sample?
  end

  def time
    ts = -Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield

    ts += Process.clock_gettime(Process::CLOCK_MONOTONIC)
    [ (ts * 1_000).round, 1 ].max
  end

  class Store
    def get(id)
      raise NotImplemented
    end

    def record(id, time)
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

    def get(id)
      @data[id] ||= @substore&.get(id)
    end

    def record(id, time)
      @substore&.record(id, time)
    end

    def flush
      @substore&.flush
    end
  end

  class RedisStore
    def initialize(redis)
      @redis = redis
    end
  end
end


require "api_avenger/adapter/faraday"

# ms granularity, round up, floor(1)
#

# storage
# get(id) / record(id, time) / flush

# local storage
#  - get(id) / save(id, time)
# remote storage
#  - get(id) - sync
#  - save(id, time) - buffer and async flush
