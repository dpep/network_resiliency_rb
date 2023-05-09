describe ApiAvenger::Adapter::Redis do
  let(:redis) { Redis.new }

  let(:timeout) { redis.instance_variable_get(:@client).timeout }
end
