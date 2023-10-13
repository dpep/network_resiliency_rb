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
      @n = 0
      @avg = 0.0
      @sq_dist = 0.0 # sum of squared distance from mean

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

    LUA_SCRIPT = <<~LUA
      local key = KEYS[1]
      local other_n = tonumber(ARGV[1])
      local other_avg = tonumber(ARGV[2])
      local other_sq_dist = tonumber(ARGV[3])

      local n, avg, sq_dist
      local state = redis.call('GET', key)

      if state then
        n, avg, sq_dist = string.match(state, "(%d+)|([%d.]+)|([%d.]+)")
        n = tonumber(n)
        avg = tonumber(avg) + 0.0
        sq_dist = tonumber(sq_dist) + 0.0

        local prev_n = n
        n = n + other_n

        local delta = other_avg - avg
        avg = avg + delta * other_n / n

        sq_dist = sq_dist + other_sq_dist
        sq_dist = sq_dist + (delta ^ 2) * prev_n * other_n / n
      else
        n = other_n
        avg = other_avg
        sq_dist = other_sq_dist
      end

      state = string.format('%d|%f|%f', n, avg, sq_dist)

      local ttl = 100000
      redis.call('SET', key, state, 'PX', ttl)

      return { n, tostring(avg), tostring(sq_dist) }
    LUA

    def sync(redis, key)
      self.class.sync(redis, key => self)[key]
    end

    def self.sync(redis, data)
      data.map do |key, stats|
        stats ||= new

        n, avg, sq_dist = redis.eval(
          LUA_SCRIPT,
          [ "network_resiliency:stats:#{key}" ],
          [ stats.n, stats.avg, stats.send(:sq_dist) ],
        )

        [ key, Stats.from(n: n, avg: avg, sq_dist: sq_dist) ]
      end.to_h
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
