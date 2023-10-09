module NetworkResiliency
  class Stats
    attr_reader :n, :avg

    def self.from(n, avg, sq_dist)
      new.tap do |instance|
        instance.instance_eval do
          @n = n
          @avg = avg
          @sq_dist = sq_dist
        end
      end
    end

    def initialize(values = [])
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

    def merge!(other)
      raise ArgumentError unless other.is_a?(self.class)

      if @n == 0
        @n = other.n
        @avg = other.avg
        @sq_dist = other.sq_dist
      elsif other.n > 0
        prev_n = n
        @n += other.n

        delta = other.avg - avg
        @avg += delta * other.n / n

        @sq_dist += other.sq_dist
        @sq_dist += (delta ** 2) * prev_n * other.n / n
      end

      self
    end

    def ==(other)
      return false unless other.is_a?(self.class)

      n == other.n &&
        avg == other.avg &&
        @sq_dist == other.sq_dist
    end

    protected

    attr_reader :sq_dist

    private

    def update(value)
      raise ArgumentError unless value.is_a?(Numeric)

      @n += 1

      prev_avg = @avg
      @avg += (value - @avg) / @n

      @sq_dist += (value - prev_avg) * (value - @avg)
    end
  end
end
