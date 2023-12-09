require "action_controller/railtie"
require "rspec/rails"

RSpec.configure do |rspec|
  include Rack::Test::Methods

  rspec.infer_base_class_for_anonymous_controllers = false

  # create a fresh, new Rails app
  class Application < Rails::Application
    config.load_defaults 7.0
    config.eager_load = false
    # config.logger = ActiveSupport::Logger.new($stdout)
    config.hosts.clear # disable hostname filtering
  end

  Rails.initialize! unless Rails.initialized?

  rspec.before(:example, [:rails, type: :request]) do
    # stub middleware so it's not frozen
    allow(Rails.application.config).to receive(:middleware).and_return(
      Rails.application.config.middleware.class.new
    )
  end
end
