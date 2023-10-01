describe "MockRedis", :mock_redis do
  let(:redis) { Redis.new(url: "redis://#{url}") }
  let(:url) { "localhost" }

  it { expect(redis.ping).to eq "PONG" }

  it "catches unsupported commands" do
    expect {
      redis.hello_there
    }.to raise_error Redis::CommandError
  end

  context "with timeout" do
    let(:url) { "timeout" }

    it "times out and raises an exception" do
      expect { redis.ping }.to raise_error(Redis::CannotConnectError)
    end
  end
end
