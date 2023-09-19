require_relative "lib/network_resiliency/version"
package = NetworkResiliency

Gem::Specification.new do |s|
  s.authors     = ["Daniel Pepper"]
  s.description = "..."
  s.files       = `git ls-files * ':!:spec'`.split("\n")
  s.homepage    = "https://github.com/dpep/network_resiliency_rb"
  s.license     = "MIT"
  s.name        = File.basename(__FILE__).split(".")[0]
  s.summary     = package.to_s
  s.version     = package.const_get "VERSION"

  s.required_ruby_version = ">= 3"

  s.add_development_dependency "byebug"
  s.add_development_dependency "ddtrace", ">= 1"
  s.add_development_dependency "dogstatsd-ruby", "<= 4.8.3"
  s.add_development_dependency "faraday"
  s.add_development_dependency "faraday-rack"
  s.add_development_dependency "rack"
  s.add_development_dependency "rack-test"
  s.add_development_dependency "redis"
  s.add_development_dependency "redis-client", ">= 0.10"
  s.add_development_dependency "rspec"
  s.add_development_dependency "simplecov"
end
