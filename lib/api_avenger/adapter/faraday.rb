require "faraday"

module ApiAvenger
  module Adapter
    class Faraday < ::Faraday::Middleware
      def call(env)
        puts "call: #{env.url}"

        super
      end


      # def call(env)
      #   puts "call: #{env.url}"

      #   super.on_complete do |response|
      #     byebug
      #     puts "call.on_complete"
      #   end
      # end

      # def on_request(env)
      #   puts "on_request to: #{env.url}"
      # end

      # def on_complete(env)
      #   puts "on_complete"
      # end
    end
  end
end

Faraday::Request.register_middleware(
  api_avenger: ApiAvenger::Adapter::Faraday,
)
