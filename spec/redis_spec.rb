describe NetworkResiliency::Adapter::Redis do
  # isolate this gem's retries from redis-client's own reconnect retries
  let(:redis) { Redis.new(host:, reconnect_attempts: 0) }
  let(:host) { "localhost" }
  let(:client) { redis._client }

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
        described_class.patch
      end

      it { is_expected.to be true }
      it { expect(described_class.patched?).to be true }

      it "does not double patch" do
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

    context "when the Redis client is unsupported" do
      before { redis.instance_variable_set(:@client, Object.new) }

      it "fails fast" do
        expect {
          described_class.patch(redis)
        }.to raise_error(ArgumentError, /unsupported/)
      end
    end
  end

  describe "connect" do
    subject(:connect) do
      redis.ping rescue Redis::CannotConnectError

      NetworkResiliency
    end

    before do
      described_class.patch(redis)
      allow(NetworkResiliency).to receive(:record)
    end

    it "logs connection" do
      is_expected.to have_received(:record).with(
        adapter: :redis,
        action: :connect,
        destination: host,
        duration: be_a(Numeric),
        error: nil,
        timeout: be_a(Numeric),
        attempts: 1,
      )
    end

    it { expect(redis.ping).to eq "PONG" }

    context "when server connection times out" do
      before do
        allow(Socket).to receive(:tcp).and_raise(Errno::ETIMEDOUT)
      end

      it "raises an error" do
        expect { redis.ping }.to raise_error(Redis::CannotConnectError)
      end

      it "logs the underlying error" do
        is_expected.to have_received(:record).with(
          include(action: :connect, error: Errno::ETIMEDOUT),
        )
      end
    end

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.disable! }

      it { expect(redis.ping).to eq "PONG" }
      it { is_expected.not_to have_received(:record) }
    end

    describe "resilient mode" do
      before do
        NetworkResiliency.mode = :resilient

        allow(NetworkResiliency).to receive(:timeouts_for) { timeouts.dup }
      end

      let(:default_timeout) { RedisClient::Config::DEFAULT_TIMEOUT }
      let(:timeouts) { [ 0.5, 2 ].freeze }

      it { expect(redis.ping).to eq "PONG" }

      it "dynamically adjusts the timeout" do
        expect(RedisClient::RubyConnection).to receive(:new).and_wrap_original do |original, *args, **kwargs|
          expect(kwargs[:connect_timeout]).to eq timeouts.first

          original.call(*args, **kwargs)
        end

        connect
      end

      it "restores the original timeout" do
        connect

        expect(client.connect_timeout).to eq default_timeout
      end

      context "when server connection times out" do
        before do
          allow(Socket).to receive(:tcp).and_raise(Errno::ETIMEDOUT)
        end

        it "raises an error" do
          expect { redis.ping }.to raise_error(Redis::CannotConnectError)
        end

        it "retries, adjusting the timeout each time" do
          attempt = 0
          expect(RedisClient::RubyConnection).to receive(:new).twice.and_wrap_original do |original, *args, **kwargs|
            expect(kwargs[:connect_timeout]).to eq timeouts[attempt]
            attempt += 1

            original.call(*args, **kwargs)
          end

          connect
        end

        it "logs the failed attempts" do
          is_expected.to have_received(:record).with(
            include(
              action: :connect,
              error: Errno::ETIMEDOUT,
              attempts: 2,
            ),
          )
        end
      end

      context "when server connects on the second attempt" do
        before do
          allow(Socket).to receive(:tcp).and_wrap_original do |original, *args, **kwargs|
            if @attempted.nil?
              @attempted = true
              raise Errno::ETIMEDOUT
            end

            original.call(*args, **kwargs)
          end
        end

        it { expect(redis.ping).to eq "PONG" }

        it "logs" do
          is_expected.to have_received(:record).with(
            include(
              action: :connect,
              error: nil,
              attempts: 2,
            ),
          )
        end
      end
    end
  end

  describe "call" do
    subject(:ping) do
      redis.ping rescue Redis::BaseConnectionError

      NetworkResiliency
    end

    before do
      described_class.patch(redis)
      allow(NetworkResiliency).to receive(:record)
    end

    it "logs request" do
      is_expected.to have_received(:record).with(
        adapter: :redis,
        action: :request,
        destination: "#{host}:ping",
        duration: be_a(Numeric),
        error: nil,
        timeout: be_a(Numeric),
        attempts: 1,
      )
    end

    it "logs both connect and request" do
      is_expected.to have_received(:record).with(include(action: :connect))
      is_expected.to have_received(:record).with(include(action: :request))
    end

    it { expect(redis.ping).to eq "PONG" }

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.disable! }

      it { expect(redis.ping).to eq "PONG" }
      it { is_expected.not_to have_received(:record) }
    end

    context "when the request times out" do
      before do
        allow_any_instance_of(RedisClient::RubyConnection).to receive(:call).and_raise(RedisClient::ReadTimeoutError)
      end

      it "raises an error" do
        expect { redis.ping }.to raise_error(Redis::TimeoutError)
      end

      it "logs the underlying error" do
        is_expected.to have_received(:record).with(
          include(action: :request, error: RedisClient::ReadTimeoutError),
        )
      end
    end

    describe "resilient mode" do
      before do
        NetworkResiliency.mode = :resilient

        allow(NetworkResiliency).to receive(:timeouts_for) { timeouts.dup }
      end

      let(:timeouts) { [ 0.5, 2 ].freeze }

      context "when server times out" do
        it "retries, adjusting the timeout each time" do
          # redis-client reconnects after a timeout, so each attempt is a new connection
          attempts = []
          allow_any_instance_of(RedisClient::RubyConnection).to receive(:call) do
            attempts << client.read_timeout
            raise RedisClient::ReadTimeoutError
          end

          ping

          expect(attempts).to eq timeouts
        end

        it "restores the original timeout" do
          allow_any_instance_of(RedisClient::RubyConnection).to receive(:call).and_raise(RedisClient::ReadTimeoutError)

          expect { ping }.not_to change(client, :read_timeout)
        end
      end

      context "when request succeeds on the second attempt" do
        before do
          allow_any_instance_of(RedisClient::RubyConnection).to receive(:call).and_wrap_original do |original, *args|
            if @attempted.nil?
              @attempted = true
              raise RedisClient::ReadTimeoutError
            end

            original.call(*args)
          end
        end

        it { expect(redis.ping).to eq "PONG" }

        it "logs" do
          is_expected.to have_received(:record).with(
            include(
              action: :request,
              error: nil,
              attempts: 2,
            ),
          )
        end
      end

      context "when command is not idempotent" do
        subject(:command) do
          redis.eval("return 'PING'") rescue Redis::TimeoutError
        end

        it "does not retry, using the most lenient timeout" do
          attempts = []
          allow_any_instance_of(RedisClient::RubyConnection).to receive(:call) do
            attempts << client.read_timeout
            raise RedisClient::ReadTimeoutError
          end

          command

          expect(attempts).to eq [ timeouts.last ]
        end
      end

      context "when command has many arguments" do
        subject(:command) do
          keys = 12.times.map { |i| "key_#{i}" }
          redis.mget(*keys)
        end

        it "augments the destination with an order of magnitude" do
          command

          expect(NetworkResiliency).to have_received(:record).with(
            include(destination: "#{host}:mget:10"),
          )
        end
      end
    end
  end
end
