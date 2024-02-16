module NetworkResiliency
  class Stats
    attr_reader :n, :avg

    class << self
      def from(n:, avg:, sq_dist:)
        new.tap do |instance|
          instance.instance_eval do
            @n = n.to_i
            @avg = avg.to_f
            @sq_dist = sq_dist.to_f
          end
        end
      end

      private

      def synchronize(fn_name)
        make_private = private_method_defined?(fn_name)
        fn = instance_method(fn_name)

        define_method(fn_name) do |*args|
          @lock.synchronize { fn.bind(self).call(*args) }
        end
        private fn_name if make_private
      end
    end

    def initialize(values = [])
      @lock = Thread::Mutex.new
      reset

      values.each {|x| update(x) }
    end

    def <<(value)
      case value
      when Array
        value.each {|x| update(x) }
      when self.class
        merge!(value)
      else
        update(value)
      end

      self
    end

    def variance(sample: false)
      @n == 0 ? 0 : @sq_dist / (sample ? (@n - 1) : @n)
    end

    def stdev
      Math.sqrt(variance)
    end

    def merge(other)
      dup.merge!(other)
    end
    alias_method :+, :merge

    synchronize def merge!(other)
      raise ArgumentError unless other.is_a?(self.class)

      if @n == 0
        @n = other.n
        @avg = other.avg
        @sq_dist = other.sq_dist
      elsif other.n > 0
        prev_n = @n
        @n += other.n

        delta = other.avg - avg
        @avg += delta * other.n / @n

        @sq_dist += other.sq_dist
        @sq_dist += (delta ** 2) * prev_n * other.n / @n
      end

      self
    end

    def ==(other)
      return false unless other.is_a?(self.class)

      @n == other.n &&
        @avg == other.avg &&
        @sq_dist == other.sq_dist
    end

    synchronize def reset
      @n = 0
      @avg = 0.0
      @sq_dist = 0.0 # sum of squared distance from mean
    end

    MIN_SAMPLE_SIZE = 1000
    MAX_WINDOW_LENGTH = 1000
    STATS_TTL = 24 * 60 * 60 # 1 day
    CACHE_TTL = 120 # seconds

    LUA_SCRIPT = <<~LUA
      local results = {}

      for i = 0, #KEYS / 2 - 1 do
        local state_key = KEYS[i * 2 + 1]
        local cache_key = KEYS[i * 2 + 2]

        local n = tonumber(ARGV[i * 3 + 1])
        local avg = ARGV[i * 3 + 2]
        local sq_dist = math.floor(ARGV[i * 3 + 3])

        if n > 0 then
          -- save new data
          local window_len = redis.call(
            'LPUSH',
            state_key,
            string.format('%d|%f|%d', n, avg, sq_dist)
          )
          redis.call('EXPIRE', state_key, #{STATS_TTL})

          if window_len > #{MAX_WINDOW_LENGTH} then
            -- trim stats to window length
            redis.call('LTRIM', state_key, 0, #{MAX_WINDOW_LENGTH - 1})
          end
        end

        -- retrieve aggregated stats

        local cached_stats = redis.call('GET', cache_key)
        if cached_stats then
          -- use cached stats
          n, avg, sq_dist = string.match(cached_stats, "(%d+)|([%d.]+)|(%d+)")
          n = tonumber(n)
        else
          -- calculate aggregated stats
          n = 0
          avg = 0.0
          sq_dist = 0

          local stats = redis.call('LRANGE', state_key, 0, -1)
          for _, entry in ipairs(stats) do
            local other_n, other_avg, other_sq_dist = string.match(entry, "(%d+)|([%d.]+)|(%d+)")
            other_n = tonumber(other_n)
            other_avg = tonumber(other_avg) + 0.0
            other_sq_dist = tonumber(other_sq_dist)

            local prev_n = n
            n = n + other_n

            local delta = other_avg - avg
            avg = avg + delta * other_n / n

            sq_dist = sq_dist + other_sq_dist
            sq_dist = sq_dist + (delta ^ 2) * prev_n * other_n / n
          end

          -- update cache
          if n >= #{MIN_SAMPLE_SIZE} then
            cached_stats = string.format('%d|%f|%d', n, avg, sq_dist)
            redis.call('SET', cache_key, cached_stats, 'EX', #{CACHE_TTL})
          end
        end

        -- accumulate results
        table.insert(results, n)
        table.insert(results, tostring(avg))
        table.insert(results, sq_dist)
      end

      return results
    LUA

    def sync(redis, key)
      self.class.sync(redis, key => self)[key]
    end

    def self.sync(redis, **data)
      keys = []
      args = []

      data.each do |key, stats|
        keys += [
          "network_resiliency:stats:#{key}",
          "network_resiliency:stats:cache:#{key}",
        ]

        args += [ stats.n, stats.avg, stats.send(:sq_dist) ]
      end

      res = redis.eval(LUA_SCRIPT, keys, args)
      data.keys.zip(res.each_slice(3)).to_h.transform_values! do |n, avg, sq_dist|
        Stats.from(n: n, avg: avg, sq_dist: sq_dist)
      end
    end

    def self.fetch(redis, keys)
      data = Array(keys).map { |k| [ k, new ] }.to_h
      res = sync(redis, **data)

      keys.is_a?(Array) ? res : res[keys]
    end

    def to_s
      "#<#{self.class.name}:#{object_id} n=#{n} avg=#{avg} sq_dist=#{sq_dist}>"
    end

    protected

    attr_reader :sq_dist

    private

    synchronize def update(value)
      raise ArgumentError unless value.is_a?(Numeric)

      @n += 1

      prev_avg = @avg
      @avg += (value - @avg) / @n

      @sq_dist += (value - prev_avg) * (value - @avg)
    end
  end
end
