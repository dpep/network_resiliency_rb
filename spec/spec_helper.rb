require "byebug"
require "datadog/statsd"
require "fiber"
require "pg"
require "mysql2"
require "rspec"
require "simplecov"

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

  config.before do
    NetworkResiliency.reset

    NetworkResiliency.redis = Redis.new

    NetworkResiliency.statsd = instance_double(Datadog::Statsd)
    allow(NetworkResiliency.statsd).to receive(:distribution)
    allow(NetworkResiliency.statsd).to receive(:increment)
    allow(NetworkResiliency.statsd).to receive(:time).and_yield

    # disable background sync
    allow(NetworkResiliency).to receive(:start_syncing)

    # since Timecop doesn't work with Process.clock_gettime
    allow(Process).to receive(:clock_gettime).and_return(*(1..1_000))

    Redis.new.flushall rescue nil
  end
end

Dir["./spec/support/**/*.rb"].sort.each { |f| require f }
