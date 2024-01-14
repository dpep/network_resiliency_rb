require "network_resiliency/refinements"
require "network_resiliency/stats"
require "network_resiliency/stats_engine"
require "network_resiliency/syncer"
require "network_resiliency/version"

using NetworkResiliency::Refinements

module NetworkResiliency
  module Adapter
    autoload :HTTP, "network_resiliency/adapter/http"
    autoload :Faraday, "network_resiliency/adapter/faraday"
    autoload :Redis, "network_resiliency/adapter/redis"
    autoload :Mysql, "network_resiliency/adapter/mysql"
    autoload :Postgres, "network_resiliency/adapter/postgres"
    autoload :Rails, "network_resiliency/adapter/rails"
  end

  ACTIONS = [ :connect, :request ].freeze
  ADAPTERS = [ :http, :faraday, :redis, :mysql, :postgres, :rails ].freeze
  MODE = [ :observe, :resilient ].freeze
  RESILIENCY_SIZE_THRESHOLD = 1_000

  extend self

  attr_accessor :statsd, :redis

  def configure
    yield self if block_given?

    Syncer.start(redis) if redis

    unless @patched
      # patch everything that's available
      ADAPTERS.each do |adapter|
        patch(adapter)
      rescue LoadError, NotImplementedError
      end
    end
  end

  def patch(*adapters)
    adapters.each do |adapter|
      case adapter
      when :http
        Adapter::HTTP.patch
      when :redis
        Adapter::Redis.patch
      when :mysql
        Adapter::Mysql.patch
      when :postgres
        Adapter::Postgres.patch
      when :rails
        Adapter::Rails.patch
      else
        raise NotImplementedError
      end
    end

    @patched = true
  end

  def enabled?(adapter)
    return thread_state["enabled"] if thread_state.key?("enabled")
    return true if @enabled.nil?

    if @enabled.is_a?(Proc)
      # prevent recursive calls
      disable! { !!@enabled.call(adapter) }
    else
      @enabled
    end
  rescue
    false
  end

  def enabled=(enabled)
    unless [ true, false ].include?(enabled) || enabled.is_a?(Proc)
      raise ArgumentError
    end

    @enabled = enabled
  end

  def enable!
    thread_state["enabled"] = true

    yield if block_given?
  ensure
    thread_state.delete("enabled") if block_given?
  end

  def disable!
    thread_state["enabled"] = false

    yield if block_given?
  ensure
    thread_state.delete("enabled") if block_given?
  end

  def timestamp
    # milliseconds
    Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000
  end

  def mode(action)
    unless ACTIONS.include?(action)
      raise ArgumentError, "invalid NetworkResiliency action: #{action}"
    end

    return thread_state[:mode] if thread_state.key?(:mode)

    mode = if @mode.is_a?(Proc)
      # prevent recursion
      observe! { @mode.call(action) }
    elsif @mode
      @mode[action]
    end || :observe

    unless MODE.include?(mode)
      raise ArgumentError, "invalid NetworkResiliency mode: #{mode}"
    end

    mode
  rescue => e
    NetworkResiliency.statsd&.increment(
      "network_resiliency.error",
      tags: {
        method: __method__,
        type: e.class,
      },
    )

    warn "[ERROR] NetworkResiliency: #{e.class}: #{e.message}"

    :observe
  end

  def mode=(mode)
    @mode = {}

    case mode
    when Proc
      @mode = mode
    when Hash
      invalid = mode.keys - ACTIONS

      unless invalid.empty?
        raise ArgumentError, "invalid actions for mode: #{invalid}"
      end

      mode.each do |action, mode|
        unless MODE.include?(mode)
          raise ArgumentError, "invalid NetworkResiliency mode for #{action}: #{mode}"
        end

        @mode[action] = mode
      end
    else
      unless MODE.include?(mode)
        raise ArgumentError, "invalid NetworkResiliency mode: #{mode}"
      end

      ACTIONS.each { |action| @mode[action] = mode }
    end

    @mode.freeze if @mode.is_a?(Hash)
  end

  def observe!
    thread_state[:mode] = :observe

    yield if block_given?
  ensure
    thread_state.delete(:mode) if block_given?
  end

  def deadline
    thread_state["deadline"]
  end

  def deadline=(ts)
    thread_state["deadline"] = case ts
    when Numeric
      Time.now + ts
    when Time
      ts
    when nil
      nil
    else
      raise ArgumentError, "invalid deadline: #{ts}"
    end

    # warn or raise if we're already past the deadline?
  end

  def normalize_request(adapter, request = nil, **context, &block)
    unless ADAPTERS.include?(adapter)
      raise ArgumentError, "invalid adapter: #{adapter}"
    end

    if request && block_given?
      raise ArgumentError, "specify request or block, but not both"
    end

    if request.nil? && !context.empty?
      raise ArgumentError, "can not speficy context without request"
    end

    @normalize_request ||= {}
    @normalize_request[adapter] ||= []
    @normalize_request[adapter] << block if block_given?

    if request
      @normalize_request[adapter].reduce(request) do |req, block|
        block.call(req, **context)
      end
    else
      @normalize_request[adapter]
    end
  end

  # private

  def record(adapter:, action:, destination:, duration:, error:, timeout:, attempts: 1)
    return if ignore_destination?(adapter, action, destination)

    NetworkResiliency.statsd&.distribution(
      "network_resiliency.#{action}",
      duration,
      tags: {
        adapter: adapter,
        destination: destination,
        error: error,
        mode: mode(action),
        attempts: (attempts if attempts > 1),
        deadline_exceeded: (Time.now >= deadline if deadline),
      }.compact,
    )

    NetworkResiliency.statsd&.gauge(
      "network_resiliency.#{action}.timeout",
      timeout,
      tags: {
        adapter: adapter,
        destination: destination,
      },
    ) if timeout && timeout > 0

    if error
      NetworkResiliency.statsd&.distribution(
        "network_resiliency.#{action}.time_saved",
        timeout - duration,
        tags: {
          adapter: adapter,
          destination: destination,
        },
      ) if timeout && timeout > duration
    else
      # record stats
      key = [ adapter, action, destination ].join(":")
      stats = StatsEngine.add(key, duration)
      tags = {
        adapter: adapter,
        destination: destination,
        n: stats.n.order_of_magnitude,
        sync: Syncer.syncing?,
      }

      NetworkResiliency.statsd&.distribution(
        "network_resiliency.#{action}.stats.n",
        stats.n,
        tags: tags,
      )

      NetworkResiliency.statsd&.distribution(
        "network_resiliency.#{action}.stats.avg",
        stats.avg,
        tags: tags,
      )

      NetworkResiliency.statsd&.distribution(
        "network_resiliency.#{action}.stats.stdev",
        stats.stdev,
        tags: tags,
      )
    end

    nil
  rescue => e
    NetworkResiliency.statsd&.increment(
      "network_resiliency.error",
      tags: {
        method: __method__,
        type: e.class,
      },
    )

    warn "[ERROR] NetworkResiliency: #{e.class}: #{e.message}"
  end

  IP_ADDRESS_REGEX = /\d{1,3}(\.\d{1,3}){3}/

  def ignore_destination?(adapter, action, destination)
    # filter raw IP addresses
    IP_ADDRESS_REGEX.match?(destination)
  end

  def timeouts_for(adapter:, action:, destination:, max: nil, units: :ms)
    default = [ max ]

    return default if NetworkResiliency.mode(action.to_sym) == :observe

    key = [ adapter, action, destination ].join(":")
    stats = StatsEngine.get(key)

    return default unless stats.n >= RESILIENCY_SIZE_THRESHOLD

    tags = {
      adapter: adapter,
      action: action,
      destination: destination,
    }

    p99 = (stats.avg + stats.stdev * 3).order_of_magnitude(ceil: true)

    timeouts = []

    if max
      max *= 1_000 if units == :s || units == :seconds

      if p99 < max
        timeouts << p99

        # fallback attempt
        if max - p99 > p99
          # use remaining time for second attempt
          timeouts << max - p99
        else
          timeouts << max

          NetworkResiliency.statsd&.increment(
            "network_resiliency.timeout.raised",
            tags: tags,
          )
        end
      else
        # the specified timeout is less than our expected p99...awkward
        timeouts << max

        NetworkResiliency.statsd&.increment(
          "network_resiliency.timeout.too_low",
          tags: tags,
        )
      end
    else
      timeouts << p99

      # timeouts << p99 * 10 if NetworkResiliency.mode(action) == :resolute

      # unbounded second attempt
      timeouts << nil

      NetworkResiliency.statsd&.increment(
        "network_resiliency.timeout.missing",
        tags: tags,
      )
    end

    NetworkResiliency.statsd&.distribution(
      "network_resiliency.#{action}.timeout.dynamic",
      timeouts[0],
      tags: {
        adapter: adapter,
        destination: destination,
      },
    )

    case units
    when nil, :ms, :milliseconds
      timeouts
    when :s, :seconds
      timeouts.map { |t| t.to_f / 1_000 if t }
    else
      raise ArgumentError, "invalid units: #{units}"
    end
  rescue => e
    NetworkResiliency.statsd&.increment(
      "network_resiliency.error",
      tags: {
        method: __method__,
        type: e.class,
      },
    )

    warn "[ERROR] NetworkResiliency: #{e.class}: #{e.message}"

    default
  end

  def reset
    @enabled = nil
    @mode = nil
    @normalize_request = nil
    @patched = nil
    Thread.current["network_resiliency"] = nil
    StatsEngine.reset
    Syncer.stop
  end

  # private

  def thread_state
    Thread.current["network_resiliency"] ||= {}
  end
end
