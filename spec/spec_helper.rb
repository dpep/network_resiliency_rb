require "byebug"
require "datadog/statsd"
require "fiber"
require "pg"
require "mysql2"
require 'rack/test'
require 'rails'
require "rspec"
require "simplecov"
require "timecop"

SimpleCov.start do
  add_filter "spec/"
end

if ENV["CI"] == "true" || ENV["CODECOV_TOKEN"]
  require "simplecov_json_formatter"
  SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
end

# load this gem
gem_name = Dir.glob("*.gemspec")[0].split(".")[0]
require gem_name

RSpec.configure do |config|
  # allow "fit" examples
  config.filter_run_when_matching :focus

  config.mock_with :rspec do |mocks|
    # verify existence of stubbed methods
    mocks.verify_partial_doubles = true
  end

  config.before do |example|
    NetworkResiliency.reset

    NetworkResiliency.redis = Redis.new
    NetworkResiliency.redis.flushall

    NetworkResiliency.statsd = instance_double(Datadog::Statsd)
    allow(NetworkResiliency.statsd).to receive(:distribution)
    allow(NetworkResiliency.statsd).to receive(:increment)
    allow(NetworkResiliency.statsd).to receive(:gauge)
    allow(NetworkResiliency.statsd).to receive(:time).and_yield

    # surface errors instead of failing quietly
    allow(NetworkResiliency.statsd).to receive(:increment).with("network_resiliency.error", any_args) do
      raise $!
    end unless example.metadata[:safely]

    # disable background sync
    allow(NetworkResiliency::Syncer).to receive(:start)

    # since Timecop doesn't work with Process.clock_gettime
    allow(Process).to receive(:clock_gettime).and_return(*(1..1_000))

    # stub adapters so patches reset after each example
    stub_const("Mysql2::Client", Class.new(Mysql2::Client))
    stub_const("Net::HTTP", Class.new(Net::HTTP))
    stub_const("PG::Connection", Class.new(PG::Connection))
    stub_const("Redis::Client", Class.new(Redis::Client))
  end

  # Timecop: freeze time
  config.around(:each) do |example|
    # only with blocks
    Timecop.safe_mode = true

    # Freeze time by default
    Timecop.freeze do
      example.run
    end
  end
end

Dir["./spec/support/**/*.rb"].sort.each { |f| require f }
