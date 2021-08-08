#!/usr/bin/env ruby

$LOAD_PATH.unshift 'lib'
require 'api_avenger'

$VERBOSE = $VERBOSE.tap do
  $VERBOSE = nil
  Dir["./lib/**/*.rb"].sort.each { |f| load f }
end

require 'byebug'
require 'faraday'


# env.request.timeout

class ApiSimulator
  def call(env)
    puts "ApiSimulator#call"
    time = env['HTTP_SLEEP']&.to_f
    puts "sleeping #{time}" if time
    sleep time if time
    [ 200, {'Content-Type' => 'text/html'}, ["OK"] ]
  end
end

faraday = Faraday.new do |f|
  f.adapter :rack, ApiSimulator.new
  f.use ApiAvenger::Adaptor::Faraday
  # f.request.timeout = 0.1
end

faraday.get('/foo', nil, { SLEEP: 1 })
puts "done"

# conn.get do |req|
#   req.url '/search'
#   req.options.timeout = 5
# end
# conn = Faraday.new('http://sushi.com', request: { timeout: 5 })
