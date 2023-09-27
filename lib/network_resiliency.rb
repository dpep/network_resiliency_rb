require "network_resiliency/version"

module NetworkResiliency
  module Adapter
    autoload :HTTP, "network_resiliency/adapter/http"
    autoload :Faraday, "network_resiliency/adapter/faraday"
    autoload :Redis, "network_resiliency/adapter/redis"
  end

  extend self

  attr_accessor :statsd

  def configure
    yield self
  end

  def enabled?(adapter)
    return true if @enabled.nil?

    @enabled.is_a?(Proc) ? @enabled.call(adapter) : @enabled
  end

  def enabled=(enabled)
    unless [ true, false ].include?(enabled) || enabled.is_a?(Proc)
      raise ArgumentError
    end

    @enabled = enabled
  end

  def enable!
    original = @enabled
    @enabled = true

    yield if block_given?
  ensure
    @enabled = original if block_given?
  end

  def disable!
    original = @enabled
    @enabled = false

    yield if block_given?
  ensure
    @enabled = original if block_given?
  end

  def timestamp
    # milliseconds
    Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000
  end

  def reset
    @enabled = nil
  end
end
