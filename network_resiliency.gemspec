require_relative "lib/network_resiliency/version"

# frozen_string_literal: true

if ENV["CIRCLECI"] == "true" && ENV["GEM_PUBLISH"] == "true"
  patch = ENV["GIT_COMMITTED_AT_DATETIME"]
  patch += ".pre.#{ENV["CIRCLE_BUILD_NUM"]}" if ENV["CIRCLE_BRANCH"] != "main"
else
  patch = "local"
end

Gem::Specification.new do |spec|
  spec.name    = "test"
  spec.version = "0.0.#{patch}"
  spec.authors = ["Chime Financial"]

  spec.homepage    = "https://github.com/1debit/network_resiliency_rb"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.0")

  spec.metadata = {
    "github_repo" => spec.homepage,
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    %x(git ls-files -z).split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec_junit_formatter"
  spec.add_development_dependency "rubocop-chime", ">= 3.0.20230905235856"
  spec.add_development_dependency "simplecov", "~> 0.17.0"

  spec.add_development_dependency "byebug"
  spec.add_development_dependency "ddtrace", ">= 1"
  spec.add_development_dependency "dogstatsd-ruby", "<= 4.8.3"
  spec.add_development_dependency "faraday", "~> 1"
  spec.add_development_dependency "faraday-rack"
  spec.add_development_dependency "mysql2", ">= 0.5"
  spec.add_development_dependency "pg", "~> 1.1"
  spec.add_development_dependency "rack"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "rails", ">= 5"
  spec.add_development_dependency "redis", "~> 4"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "timecop"
end

