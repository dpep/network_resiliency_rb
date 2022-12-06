module ApiAvenger
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
      @sq_dist / (sample ? (@n - 1) : @n)
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

      prev_n = n
      @n += other.n

      delta = other.avg - avg
      @avg += delta * other.n / n

      @sq_dist += other.instance_variable_get(:@sq_dist)
      @sq_dist += (delta ** 2) * prev_n * other.n / n

      self
    end

    private

    def update(value)
      raise ArgumentError unless value.is_a?(Numeric)

      @n += 1

      prev_avg = @avg
      @avg += (value - @avg) / @n

      @sq_dist += (value - prev_avg) * (value - @avg)
      # @sq_dist += (sq_dist - @sq_dist) / @n

# for x, w in data_weight_pairs:
#   w_sum = w_sum + w
#   mean_old = mean
#   mean = mean_old + (w / w_sum) * (x - mean_old)
#   S = S + w * (x - mean_old) * (x - mean)

  # count += 1
  # delta = newValue - mean
  # mean += delta / count
  # delta2 = newValue - mean
  # M2 += delta * delta2
    end
  end
end
