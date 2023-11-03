require "network_resiliency/refinements"
require "network_resiliency/stats"
require "network_resiliency/stats_engine"
require "network_resiliency/version"

using NetworkResiliency::Refinements

module NetworkResiliency
  module Adapter
    autoload :HTTP, "network_resiliency/adapter/http"
    autoload :Faraday, "network_resiliency/adapter/faraday"
    autoload :Redis, "network_resiliency/adapter/redis"
    autoload :Mysql, "network_resiliency/adapter/mysql"
    autoload :Postgres, "network_resiliency/adapter/postgres"
  end

  extend self

  attr_accessor :statsd, :redis

  def configure
    yield self if block_given?

    start_syncing if redis
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
      else
        raise NotImplementedError
      end
    end
  end

  def enabled?(adapter)
    return thread_state["enabled"] if thread_state.key?("enabled")
    return true if @enabled.nil?

    if @enabled.is_a?(Proc)
      # prevent recursive calls
      enabled = @enabled
      disable! { !!enabled.call(adapter) }
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
    original = @enabled
    thread_state["enabled"] = true

    yield if block_given?
  ensure
    thread_state.delete("enabled") if block_given?
  end

  def disable!
    original = @enabled
    thread_state["enabled"] = false

    yield if block_given?
  ensure
    thread_state.delete("enabled") if block_given?
  end

  def timestamp
    # milliseconds
    Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000
  end

  # private

  def record(adapter:, action:, destination:, duration:, error: nil)
    return if ignore_destination?(adapter, action, destination)

    NetworkResiliency.statsd&.distribution(
      "network_resiliency.#{action}",
      duration,
      tags: {
        adapter: adapter,
        destination: destination,
        error: error,
      }.compact,
    )

    NetworkResiliency.statsd&.distribution(
      "network_resiliency.#{action}.magnitude",
      duration.order_of_magnitude(ceil: true),
      tags: {
        adapter: adapter,
        destination: destination,
        error: error,
      }.compact,
    )

    key = [ adapter, action, destination ].join(":")
    StatsEngine.add(key, duration).tap do |stats|
      tags = {
        adapter: adapter,
        destination: destination,
        n: stats.n.order_of_magnitude,
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

  IP_ADDRESS_REGEX = Regexp.new(/\d{1,3}(\.\d{1,3}){3}/)

  def ignore_destination?(adapter, action, destination)
    # filter raw IP addresses
    IP_ADDRESS_REGEX.match?(destination)
  end

  def reset
    @enabled = nil
    Thread.current["network_resiliency"] = nil
    StatsEngine.reset
    @sync_worker.kill if @sync_worker
  end

  private

  def thread_state
    Thread.current["network_resiliency"] ||= {}
  end

  def start_syncing
    @sync_worker.kill if @sync_worker

    raise "Redis not configured" unless redis

    @sync_worker = Thread.new do
      while true do
        StatsEngine.sync(redis)

        sleep(3)
      end
    rescue Interrupt
      # goodbye
    end
  end
end
