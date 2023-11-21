describe NetworkResiliency::Adapter::Redis, :mock_redis do
  let(:redis) { Redis.new(url: "redis://#{host}") }
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
    subject(:connect) do
      client rescue Redis::CannotConnectError

      NetworkResiliency
    end

    let(:client) { redis._client.connect }

    before do
      described_class.patch(redis)
      allow(NetworkResiliency).to receive(:record)
    end

    it "logs connection" do
      is_expected.to have_received(:record).with(
        adapter: "redis",
        action: "connect",
        destination: host,
        duration: be_a(Numeric),
        error: nil,
        timeout: be_a(Numeric),
        attempts: be_an(Integer),
      )
    end

    it { expect(client).to be_connected }

    context "when server connection times out" do
      before do
        allow(Redis::Connection::Ruby).to receive(:connect).and_raise(Redis::TimeoutError)
      end

      it "raises an error" do
        expect { client }.to raise_error(Redis::CannotConnectError)
      end

      it "logs the underlying error" do
        is_expected.to have_received(:record).with(
          include(error: Redis::TimeoutError),
        )
      end
    end

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.disable! }

      it "does not call datadog" do
        is_expected.not_to have_received(:record)
      end

      context "when server connection times out" do
        let(:host) { "timeout" }

        it "raises an error" do
          expect { client }.to raise_error(Redis::CannotConnectError)
        end

        it "does not log timeout" do
          is_expected.not_to have_received(:record)
        end
      end
    end

    describe "resilient mode" do
      before do
        NetworkResiliency.mode = :resilient

        allow(NetworkResiliency).to receive(:timeouts_for) { timeouts.dup }
      end

      let(:default_timeout) { Redis::Client::DEFAULTS[:timeout] }
      let(:timeouts) { [ 10, 100 ].freeze }

      it { expect(client).to be_connected }
      it { expect(client.connect_timeout).to eq default_timeout }
      it { expect(timeouts.first).not_to eq default_timeout }

      it "dynamically adjusts the timeout" do
        expect(Redis::Connection::Ruby).to receive(:connect) do |config|
          expect(config[:connect_timeout]).to eq timeouts.first
        end

        connect
      end

      it "restores the original timeout" do
        connect

        expect(client.connect_timeout).to eq default_timeout
      end

      context "when server connection times out" do
        let(:host) { "timeout" }

        it "raises an error" do
          expect { client }.to raise_error(Redis::CannotConnectError)
        end

        it "logs timeout" do
          is_expected.to have_received(:record).with(
            include(error: Redis::TimeoutError),
          )
        end

        it "retries" do
          expect(Redis::Connection::Ruby).to receive(:connect).twice

          connect
        end

        it "dynamically adjusts the timeout each time" do
          attempt = 0
          expect(Redis::Connection::Ruby).to receive(:connect).twice do |config|
            expect(config[:connect_timeout]).to eq timeouts[attempt]

            attempt += 1

            raise Redis::TimeoutError
          end

          connect
        end

        it "logs the failed attempts" do
          is_expected.to have_received(:record).with(
            include(
              error: Redis::TimeoutError,
              attempts: 2,
            ),
          )
        end
      end

      context "when server connects on the second attempt" do
        before do
          allow(Redis::Connection::Ruby).to receive(:connect) do
            if @attempted.nil?
              @attempted = true
              raise Redis::TimeoutError
            end

            mock_redis(host: host)
          end
        end

        it { expect(client).to be_connected }

        it "logs" do
          is_expected.to have_received(:record).with(
            include(
              error: nil,
              attempts: 2,
            ),
          )
        end
      end
    end
  end

  describe ".call" do
    subject(:ping) do
      redis.ping rescue Redis::CannotConnectError

      NetworkResiliency
    end
    let(:client) { redis._client }

    before do
      described_class.patch(redis)
      allow(NetworkResiliency).to receive(:record)
    end

    it "logs connection" do
      is_expected.to have_received(:record).with(
        adapter: "redis",
        action: "request",
        destination: "#{host}:ping",
        duration: be_a(Numeric),
        error: nil,
        timeout: be_a(Numeric),
        attempts: be_an(Integer),
      )
    end

    it "logs both connect and request" do
      is_expected.to have_received(:record).with(include(action: "connect"))
      is_expected.to have_received(:record).with(include(action: "request"))
    end

    it { expect(redis.ping).to eq "PONG" }

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.disable! }

      it { expect(redis.ping).to eq "PONG" }
      it { is_expected.not_to have_received(:record) }
    end

    context "when there is a System Error" do
      before do
        allow(client).to receive(:read).and_raise(Errno::ETIMEDOUT)
      end

      it "logs the error" do
        is_expected.to have_received(:record).with(
          include(error: Errno::ETIMEDOUT),
        )
      end
    end

    describe "resilient mode" do
      before do
        NetworkResiliency.mode = :resilient

        allow(NetworkResiliency).to receive(:timeouts_for) { timeouts.dup }
      end

      let(:default_timeout) { Redis::Client::DEFAULTS[:timeout] }
      let(:timeouts) { [ 10, 100 ].freeze }

      context "when server times out" do
        it "retries" do
          expect(client).to receive(:read).twice.and_raise(Redis::TimeoutError)

          ping
        end

        it "dynamically adjusts the timeout each time" do
          attempt = 0
          expect(client).to receive(:read).twice do
            expect(client.options[:read_timeout]).to eq timeouts[attempt]

            attempt += 1

            raise Redis::TimeoutError
          end

          ping
        end
      end

      context "when request succeeds on the second attempt" do
        before do
          allow(client).to receive(:read).and_wrap_original do |original, *args|
            if @attempted.nil?
              @attempted = true
              raise Redis::TimeoutError
            end

            original.call(*args)
          end
        end

        it { expect(redis.ping).to eq "PONG" }

        it "logs" do
          is_expected.to have_received(:record).with(
            include(
              error: nil,
              attempts: 2,
            ),
          )
        end
      end

      context "when command is not idepotent" do
        subject(:command) do
          redis.eval("retrun 'PING'") rescue Redis::TimeoutError
        end

        it "does not retry" do
          expect(client).to receive(:read).once.and_raise(Redis::TimeoutError)

          command
        end

        it "uses the most lenient timeout" do
          expect(client).to receive(:read) do
            expect(client.options[:read_timeout]).to eq timeouts.last
          end

          command
        end
      end

      context "when command has many arguments" do
        subject(:command) do
          keys = 12.times.map { |i| "key_#{i}" }
          redis.mget(*keys) rescue Redis::CommandError
        end

        it "augments the destination with an order of magnitude" do
          expect(NetworkResiliency).to receive(:record).with(
            include(destination: "#{host}:mget:10"),
          )

          command
        end
      end
    end
  end
end
