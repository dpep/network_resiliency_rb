module ApiAvenger
  class Stats
    attr_reader :n, :avg, :variance

    def initialize(values = [])
      @n = 0
      @avg = @variance = 0.0

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

    def stdev
      Math.sqrt(variance)
    end

    def merge(other)
      dup.merge!(other)
    end
    alias_method :+, :merge

    def merge!(other)
      raise ArgumentError unless other.is_a?(self.class)

      @n += other.n
      @avg += (other.avg - avg) * other.n / n

      # approximate
      @variance += (other.variance - variance) * other.n / n

      self
    end
    alias_method :+, :merge

    private

    def update(value, weight: 1)
      raise ArgumentError if weight < 0

      return if value.nil? || weight == 0

      @n += weight

      prev_avg = @avg
      @avg += (value - @avg) * weight / @n

      sq_diff = (value - prev_avg) * (value - @avg)
      @variance += (sq_diff - @variance) * weight / @n
    end
  end
end
