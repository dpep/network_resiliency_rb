# Faraday.new do |conn|
#   conn.adapter :rack, ApiSimulator.new
# end

class HttpSimulator
  def call(env)
    puts "ApiSimulator#call"
    time = env['HTTP_SLEEP']&.to_f
    puts "sleeping #{time}" if time
    # byebug
    sleep(time) if time
    [ 200, {'Content-Type' => 'text/html'}, ["OK"] ]
  end
end
