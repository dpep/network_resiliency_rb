require "network_resiliency/refinements"

using NetworkResiliency::Refinements

module NetworkResiliency
  class PowerStats
    MIN_VALUE = 1
    LOCK = Thread::Mutex.new
    STATS = {}

    attr_reader :n

    class << self
      def [](key)
        LOCK.synchronize { STATS[key] ||= new }
      end

      def reset
        LOCK.synchronize { STATS.clear }
      end

      private

      def synchronize(fn_name)
        fn = instance_method(fn_name)

        define_method(fn_name) do |*args|
          @lock.synchronize { fn.bind(self).call(*args) }
        end
      end
    end

    def initialize(values = [])
      @lock = Thread::Mutex.new
      reset

      values.each {|x| add(x) }
    end

    def <<(value)
      case value
      when Array
        value.each {|x| add(x) }
      when self.class
        merge!(value)
      else
        add(value)
      end

      self
    end

    synchronize def add(value)
      raise ArgumentError, "Numeric expected, found #{value.class}" unless value.is_a?(Numeric)

      value = [ value, MIN_VALUE ].max
      i = Math.log10(value).ceil

      @buckets[i] ||= 0
      @buckets[i] += 1
      @n += 1
    end

    synchronize def percentile(p)
      raise ArgumentError, "Percentile must be between 0 and 100" unless p.between?(0, 100)

      return 0 if @n == 0

      threshold = ((100 - p) / 100.0 * @n).floor
      index = @buckets.size - 1

      while index >= 0
        if @buckets[index]
          break if @buckets[index] >= threshold

          threshold -= @buckets[index]
        end

        index -= 1
      end

      10 ** index
    end
    alias_method :p, :percentile

    def p99
      percentile(99)
    end

    def merge(other)
      dup.merge!(other)
    end
    alias_method :+, :merge

    synchronize def merge!(other)
      raise ArgumentError unless other.is_a?(self.class)

      other_buckets = other.instance_variable_get(:@buckets)

      if @n == 0
        @n = other.n
        @buckets = other_buckets.dup
      elsif other.n > 0
        @n += other.n

        other_buckets.each_with_index do |count, i|
          next unless count

          @buckets[i] ||= 0
          @buckets[i] += count
        end
      end

      self
    end

    synchronize def scale!(percentage)
      raise ArgumentError, "Numeric expected, found #{percentage.class}" unless percentage.is_a?(Numeric)
      raise ArgumentError, "argument must be between 0 and 100" unless percentage.between?(0, 100)

      factor = percentage / 100.0

      @buckets.map! {|x| (x * factor).round if x }
      @n = @buckets.compact.sum
    end

    synchronize def reset
      @n = 0
      @buckets = []
    end
  end
end
