require "pg"

describe NetworkResiliency do
  def expect_enabled
    expect(NetworkResiliency.enabled?(:http))
  end

  describe ".timestamp" do
    it "converts to milliseconds" do
      ts = -NetworkResiliency.timestamp
      ts += NetworkResiliency.timestamp

      expect(ts).to be 1_000
    end
  end

  describe ".patch" do
    let(:http) { Net::HTTP.new("example.com") }
    let(:redis) { Redis.new }

    before do
      stub_const("Mysql2::Client", Class.new(Mysql2::Client))
      stub_const("Net::HTTP", Class.new(Net::HTTP))
      stub_const("PG::Connection", Class.new(PG::Connection))
      stub_const("Redis::Client", Class.new(Redis::Client))
    end

    context "with HTTP" do
      subject { NetworkResiliency::Adapter::HTTP.patched?(http) }

      it { is_expected.to be false }

      it "patches HTTP" do
        described_class.patch(:http)

        is_expected.to be true
      end
    end

    context "with multiple adapters" do
      before do
        described_class.configure do |conf|
          conf.patch(:http, :mysql, :postgres, :redis)
        end
      end

      it "patches http" do
        expect(
          NetworkResiliency::Adapter::HTTP.patched?
        ).to be true
      end

      it "patches mysql" do
        expect(
          NetworkResiliency::Adapter::Mysql.patched?
        ).to be true
      end

      it "patches postgres" do
        expect(
          NetworkResiliency::Adapter::Postgres.patched?
        ).to be true
      end

      it "patches redis" do
        expect(
          NetworkResiliency::Adapter::Redis.patched?
        ).to be true
      end
    end

    it "catches bogus input" do
      expect {
        NetworkResiliency.patch(:foo)
      }.to raise_error(NotImplementedError)
    end
  end

  describe ".enabled?" do
    subject { NetworkResiliency.enabled?(:http) }

    it "defaults to true" do
      is_expected.to be true
    end

    context "when set to false" do
      before { NetworkResiliency.enabled = false }

      it { is_expected.to be false }
    end

    context "when set to a method" do
      let(:callback) { proc { false } }

      before do
        NetworkResiliency.enabled = callback
      end

      it "uses value returned by method" do
        is_expected.to be false
      end

      context "when method explodes" do
        let(:callback) { proc { raise } }

        it "gracefully fails closed" do
          is_expected.to be false
        end
      end

      context "when method returns non-boolean value" do
        let(:callback) { proc { nil } }

        it "is converted to a boolean" do
          is_expected.to be false
        end
      end

      context "when method recurses" do
        # eg. ->(*) { Redis.get("enabled") }

        it "disables NetworkResiliency" do
          expect(callback).to receive(:call).once do
            is_expected.to be false
          end

          NetworkResiliency.enabled?(:http)
        end
      end
    end

    context "when given an invalid argument" do
      it "fails fast" do
        expect {
          NetworkResiliency.enabled = 1
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe ".enable!" do
    before { NetworkResiliency.enabled = false }

    it "enables" do
      NetworkResiliency.enable!
      expect_enabled.to be true
    end

    it "resets after the given block" do
      NetworkResiliency.enable! do
        expect_enabled.to be true
      end

      expect_enabled.to be false
    end

    it "is thread safe" do
      expect_enabled.to be false

      fiber = Fiber.new do
        NetworkResiliency.enable! do
          expect_enabled.to be true

          Fiber.yield
        end
      end

      fiber.resume

      # Fiber paused inside enable! block
      expect_enabled.to be false

      fiber.resume

      # Fiber completed
      expect(fiber).not_to be_alive
      expect_enabled.to be false
    end
  end

  describe ".disable!" do
    before { NetworkResiliency.enabled = true }

    it "disables" do
      NetworkResiliency.disable!
      expect_enabled.to be false
    end

    it "resets after the given block" do
      NetworkResiliency.disable! do
        expect_enabled.to be false
      end

      expect_enabled.to be true
    end
  end

  describe ".configure" do
    it "yields a config object" do
      expect {|b| NetworkResiliency.configure(&b) }.to yield_control
    end

    it "configures NetworkResiliency" do
      expect_enabled.to be true

      NetworkResiliency.configure do |conf|
        conf.enabled = false
      end

      expect_enabled.to be false
    end
  end

  describe ".record" do
    subject do
      NetworkResiliency.record(
        adapter: "adapter",
        action: action,
        destination: host,
        duration: duration,
        error: error,
      )

      NetworkResiliency.statsd
    end

    let(:action) { "connect" }
    let(:error) { Net::OpenTimeout }
    let(:duration) { 10 }
    let(:host) { "example.com" }

    it "calls Datadog" do
      is_expected.to have_received(:distribution)
    end

    it "captures metric info" do
      is_expected.to have_received(:distribution).with(
        "network_resiliency.#{action}",
        duration,
        tags: include(destination: host, error: error),
      )
    end

    context "when host is a raw IP address" do
      let(:host) { "127.0.0.1" }

      it "does not call Datadog" do
        is_expected.not_to have_received(:distribution)
      end
    end
  end
end
