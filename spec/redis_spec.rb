describe NetworkResiliency::Adapter::Redis, :mock_redis do
  let(:redis) { Redis.new(url: "redis://#{host}", reconnect_attempts: 0) }
  let(:host) { "localhost" }

  describe ".patch" do
    subject { described_class.patched?(redis) }

    it { is_expected.to be false }

    context "when patched" do
      before { described_class.patch(redis) }

      it { is_expected.to be true }
    end

    it "has not patched globally" do
      expect(described_class.patched?).to be false
    end

    context "when patching globally" do
      before do
        stub_const("Redis::Client", Class.new(Redis::Client))

        described_class.patch
      end

      it { is_expected.to be true }
      it { expect(described_class.patched?).to be true }

      it "does not double patch" do
        client = redis.instance_variable_get(:@client)
        expect(client.singleton_class).not_to receive(:prepend)

        described_class.patch(redis)
      end
    end

    context "when patching a bogus object" do
      it "fails fast" do
        expect {
          described_class.patch(double)
        }.to raise_error(ArgumentError, /expected Redis/)
      end
    end

    context "when using Redis in cluster mode" do
      before do
        allow(Redis::Cluster).to receive(:new).and_return(instance_double(Redis::Cluster))
      end

      let(:redis) { Redis.new(cluster: ['redis://localhost']) }

      it "is not supported" do
        expect {
          described_class.patch(redis)
        }.to raise_error(ArgumentError, /unsupported.*Cluster/)
      end
    end
  end

  describe ".connect" do
    subject do
      redis.ping rescue Redis::CannotConnectError

      NetworkResiliency.statsd
    end

    before do
      described_class.patch(redis)
    end

    it "logs connection" do
      is_expected.to have_received(:distribution).with(
        /connect/,
        Numeric,
        anything,
      )
    end

    it "logs duration" do
      is_expected.to have_received(:distribution) do |_, duration, _|
        expect(duration).to be > 0
      end
    end

    it "tags the destination host" do
      is_expected.to have_received(:distribution).with(
        String,
        Numeric,
        tags: include(destination: host),
      )
    end

    it "completes request" do
      expect(redis.ping).to eq "PONG"
      expect(NetworkResiliency.statsd).to have_received(:distribution)
    end

    context "when server connection times out" do
      let(:host) { "timeout" }

      it "raises an error" do
        expect { redis.ping }.to raise_error(Redis::CannotConnectError)
      end

      it "logs timeout" do
        is_expected.to have_received(:distribution).with(
          String,
          Numeric,
          tags: include(error: Redis::TimeoutError),
        )
      end
    end

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.disable! }

      it "does not call datadog" do
        is_expected.not_to have_received(:distribution)
      end

      context "when server connection times out" do
        let(:host) { "timeout" }

        it "raises an error" do
          expect { redis.ping }.to raise_error(Redis::CannotConnectError)
        end

        it "does not log timeout" do
          is_expected.not_to have_received(:distribution)
        end
      end
    end
  end
end
