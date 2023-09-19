require "network_resiliency/stats"
require "network_resiliency/version"

module NetworkResiliency
  module Adapter
    autoload :HTTP, "network_resiliency/adapter/http"
    autoload :Faraday, "network_resiliency/adapter/faraday"
    autoload :Redis, "network_resiliency/adapter/redis"
  end

  extend self

  attr_accessor :statsd

  def enabled?
    return true if @enabled.nil?

    @enabled.is_a?(Proc) ? @enabled.call : @enabled
  end

  def enabled=(enabled)
    unless [ nil, true, false ].include?(enabled) || enabled.is_a?(Proc)
      raise ArgumentError
    end

    @enabled = enabled
  end

  def timestamp
    # milliseconds
    Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000
  end

  def reset
    @enabled = nil
  end
end
