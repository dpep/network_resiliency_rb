require "rspec/expectations"

RSpec::Matchers.define :approximate do |expected|
  chain :within do |percision|
    @precision = percision
  end

  match do |actual|
    raise ArgumentError unless expected.is_a?(NetworkResiliency::Stats)
    raise ArgumentError unless actual.is_a?(NetworkResiliency::Stats)

    return false unless expected.n == actual.n
    precision = @precision || 1

    expect(actual.avg).to be_within(precision).percent_of(expected.avg)
    expect(actual.stdev).to be_within(precision).percent_of(expected.stdev)
  end

  diffable
end
