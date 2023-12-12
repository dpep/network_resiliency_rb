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
        conf.mode = :resilient
      end

      expect_enabled.to be false
      expect(NetworkResiliency.mode(:connect)).to be :resilient
    end

    it "patches all available adapters by default" do
      NetworkResiliency.configure

      expect(NetworkResiliency::Adapter::HTTP.patched?).to be true
      expect(NetworkResiliency::Adapter::Redis.patched?).to be true
    end

    it "will not patch adapters if some were already patched" do
      NetworkResiliency.configure do |conf|
        conf.patch(:http)
      end

      expect(NetworkResiliency::Adapter::HTTP.patched?).to be true
      expect(NetworkResiliency::Adapter::Redis.patched?).to be false
    end

    it "will not patch adapters that aren't available" do
      expect(NetworkResiliency::Adapter::HTTP).to receive(:patch).and_raise(LoadError)

      expect { NetworkResiliency.configure }.not_to raise_error

      expect(NetworkResiliency::Adapter::HTTP.patched?).to be false
      expect(NetworkResiliency::Adapter::Redis.patched?).to be true
    end

    it "is possible to avoid patching" do
      NetworkResiliency.configure do |conf|
        conf.patch
      end

      expect(NetworkResiliency::Adapter::HTTP.patched?).to be false
      expect(NetworkResiliency::Adapter::Redis.patched?).to be false
    end

    it "will start syncing" do
      NetworkResiliency.configure
      expect(NetworkResiliency::Syncer).to have_received(:start)
    end

    context "when Redis is not configured" do
      before { NetworkResiliency.redis = nil }

      it "will not start syncing" do
        NetworkResiliency.configure
        expect(NetworkResiliency::Syncer).not_to have_received(:start)
      end
    end
  end

  describe ".mode" do
    subject { NetworkResiliency.mode(:connect) }

    it "defaults to observe" do
      is_expected.to be :observe
    end

    it "is can be set" do
      NetworkResiliency.mode = :resilient

      is_expected.to be :resilient
    end

    it "fails fast on invalid input" do
      expect {
        NetworkResiliency.mode = :foo
      }.to raise_error(ArgumentError)

      expect {
        NetworkResiliency.mode(:foo)
      }.to raise_error(ArgumentError)
    end

    it "resets" do
      NetworkResiliency.mode = :resilient
      NetworkResiliency.reset

      is_expected.to be :observe
    end

    context "when actions set to different modes" do
      before do
        NetworkResiliency.mode = { connect: :resilient }
      end

      it { is_expected.to be :resilient }

      it { expect(NetworkResiliency.mode(:request)).to be :observe }

      it "fails fast on invalid input" do
        expect {
          NetworkResiliency.mode = { connect: :foo }
        }.to raise_error(ArgumentError)

        expect {
          NetworkResiliency.mode = { conn: :observe }
        }.to raise_error(ArgumentError)
      end
    end

    context "when set to a method" do
      before do
        NetworkResiliency.mode = callback
      end

      let(:callback) do
        ->(action) { action == :connect ? :resilient : :observe }
      end

      it { is_expected.to be :resilient }

      it { expect(NetworkResiliency.mode(:request)).to be :observe }

      context "when callback returns a valid mode" do
        let(:callback) { proc { :resilient } }

        it { is_expected.to be :resilient }
      end

      context "when callback returns nil" do
        let(:callback) { proc { nil } }

        it { is_expected.to be :observe }
      end

      context "when callback returns an invalid mode" do
        let(:callback) { proc { :foo } }

        it "fails fast" do
          expect {
            subject
          }.to raise_error(ArgumentError)
        end
      end

      context "when callback explodes", :safely do
        let(:error) { RuntimeError }
        let(:callback) { proc { raise error } }

        it "warns and falls back to observe" do
          expect { subject }.to output(/ERROR/).to_stderr

          expect(described_class.statsd).to have_received(:increment).with(
            "network_resiliency.error",
            tags: {
              method: :mode,
              type: error,
            },
          )

          is_expected.to be :observe
        end
      end

      context "when callback recurses" do
        # eg. ->(*) { Redis.get("mode") }

        it "switches to observe mode during recursion" do
          expect(callback).to receive(:call).once.and_wrap_original do |orig, *args|
            is_expected.to be :observe

            orig.call(*args).tap do |mode|
              expect(mode).to be :resilient
            end
          end

          NetworkResiliency.mode(:connect)
        end
      end
    end
  end

  describe ".observe!" do
    subject { described_class.mode(:connect) }

    before { described_class.mode = :resilient }

    it { is_expected.to be :resilient }

    it "switches mode for a given block" do
      expect(described_class).to receive(:mode).once.and_call_original

      described_class.observe! do
        is_expected.to be :observe
      end
    end

    it "resets mode after the block" do
      described_class.observe! {}

      is_expected.to be :resilient
    end

    it "is resilient to errors" do
      expect {
        described_class.observe! { raise }
      }.to raise_error(RuntimeError)

      is_expected.to be :resilient
    end

    it "passes through the return value" do
      res = described_class.observe! { :woot }
      expect(res).to be :woot
    end
  end

  describe ".deadline" do
    subject { described_class.deadline }

    let(:now) { Time.now }
    let(:timeout) { 0.01 }

    it { is_expected.to be_nil }

    it "can be set to a Time" do
      described_class.deadline = now

      is_expected.to eq now
    end

    it "can be set using a timeout in seconds" do
      described_class.deadline = timeout

      is_expected.to eq now + timeout
    end

    it "can be cleared" do
      described_class.deadline = now
      described_class.deadline = nil

      is_expected.to be_nil
    end

    it "fails fast on invalid input" do
      expect {
        described_class.deadline = "foo"
      }.to raise_error(ArgumentError)
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
        timeout: timeout,
        attempts: attempts,
      )

      NetworkResiliency.statsd
    end

    let(:action) { :connect }
    let(:error) { nil }
    let(:duration) { 8 }
    let(:host) { "example.com" }
    let(:timeout) { 100 }
    let(:attempts) { 1 }

    it "captures metric info" do
      is_expected.to have_received(:distribution).with(
        "network_resiliency.#{action}",
        duration,
        tags: include(destination: host),
      )

      is_expected.to have_received(:gauge).with(
        "network_resiliency.#{action}.timeout",
        timeout,
        anything,
      )

      is_expected.to have_received(:distribution).with(
        "network_resiliency.#{action}.stats.n",
        1,
        anything,
      )

      is_expected.to have_received(:distribution).with(
        "network_resiliency.#{action}.stats.avg",
        duration,
        tags: include(n: 1),
      )
    end

    it "captures the mode" do
      is_expected.to have_received(:distribution).with(
        "network_resiliency.#{action}",
        duration,
        tags: include(mode: :observe),
      )
    end

    context "when timeout is nil" do
      let(:timeout) { nil }

      it "does not track timeout" do
        is_expected.not_to have_received(:gauge).with(
          "network_resiliency.#{action}.timeout",
          any_args,
        )
      end
    end

    context "when timeout is 0" do
      let(:timeout) { 0 }

      it "does not track timeout" do
        is_expected.not_to have_received(:gauge).with(
          "network_resiliency.#{action}.timeout",
          any_args,
        )
      end
    end

    it "does not track attempts for first time successes" do
      is_expected.to have_received(:distribution).with(
        "network_resiliency.#{action}",
        any_args,
      ) do |_, _, tags:|
        expect(tags).not_to include(:attempts)
      end
    end

    it "does not miscount successful retries" do
      is_expected.not_to have_received(:increment).with(
        "network_resiliency.#{action}.resilient",
        anything,
      )
    end

    context "with multiple attempts" do
      let(:attempts) { 2 }

      it "tracks attempts" do
        is_expected.to have_received(:distribution).with(
          "network_resiliency.#{action}",
          duration,
          tags: include(attempts: attempts),
        )
      end
    end

    context "when host is a raw IP address" do
      let(:host) { "127.0.0.1" }

      it "does not call Datadog" do
        is_expected.not_to have_received(:distribution)
      end
    end

    context "when there is a connection error" do
      let(:error) { Net::OpenTimeout }

      it "captures error info" do
        is_expected.to have_received(:distribution).with(
          "network_resiliency.#{action}",
          duration,
          tags: include(error: error),
        )
      end

      it "does not update stats" do
        expect(NetworkResiliency::StatsEngine).not_to receive(:add)

        subject
      end

      it "tracks time saved by failing fast" do
        is_expected.to have_received(:distribution).with(
          "network_resiliency.#{action}.time_saved",
          timeout - duration,
          anything,
        )
      end

      context "when there is no timeout" do
        let(:timeout) { nil }

        it "does not track time saved" do
          is_expected.not_to have_received(:distribution).with(
            "network_resiliency.#{action}.time_saved",
            any_args,
          )
        end
      end
    end

    context "when errors arise in .record itself", :safely do
      before do
        allow(NetworkResiliency::StatsEngine).to receive(:add).and_raise
      end

      it "warns, but don't explode" do
        expect { subject }.to output(/ERROR/).to_stderr

        is_expected.to have_received(:increment).with(
          "network_resiliency.error",
          tags: {
            method: :record,
            type: RuntimeError,
          },
        )
      end
    end

    context "when Datadog is not configured" do
      before { NetworkResiliency.statsd = nil }

      it "still works" do
        expect(NetworkResiliency::StatsEngine).to receive(:add).and_call_original
        subject
      end

      context "when errors arise" do
        before do
          allow(NetworkResiliency::StatsEngine).to receive(:add).and_raise
        end

        it "warns, but doesn't explode" do
          expect { subject }.to output(/ERROR/).to_stderr
        end
      end
    end
  end

  describe ".timeouts_for" do
    subject(:timeouts) do
      described_class.timeouts_for(
        adapter: :http,
        action: :connect,
        destination: "example.com",
        max: max,
        units: units,
      )
    end

    let(:stats) do
      instance_double(
        NetworkResiliency::Stats,
        n: n,
        avg: 10,
        stdev: 1,
      )
    end
    let(:n) { described_class::RESILIENCY_SIZE_THRESHOLD }
    let(:p99) { 20 }
    let(:max) { 100 }
    let(:units) { nil }

    before do
      allow(described_class::StatsEngine).to receive(:get).and_return(stats)
      described_class.mode = :resilient
    end

    it "makes two attempts" do
      is_expected.to eq [ p99, max - p99 ]
    end

    it "does not exceed the max timeout" do
      expect(timeouts.sum).to be <= max
    end

    context "when no stats are available" do
      let(:stats) { NetworkResiliency::Stats.new }

      it { is_expected.to eq [ max ] }
    end

    context "when n is too small" do
      let(:n) { described_class::RESILIENCY_SIZE_THRESHOLD - 1 }

      it { is_expected.to eq [ max ] }
    end

    context "when there is no max timeout" do
      let(:max) { nil }

      it "should make one attempt with a timeout and one unbounded attempt" do
        is_expected.to eq [ 20, nil ]
      end
    end

    context "when the max timeout is less than the expected p99" do
      let(:max) { 15 }

      it "only makes one attempt, with the max" do
        is_expected.to eq [ max ]
      end

      it "logs the event" do
        expect(NetworkResiliency.statsd).to receive(:increment).with(
          "network_resiliency.timeout.too_low",
          anything,
        )

        subject
      end
    end

    context "when the max timeout is similarly sized to the p99" do
      let(:max) { 30 }

      specify { expect(max - p99).to be < p99 }

      it "makes two attempts, using the max as the second" do
        is_expected.to eq [ p99, max ]
      end

      it "logs the event" do
        expect(NetworkResiliency.statsd).to receive(:increment).with(
          "network_resiliency.timeout.raised",
          anything,
        )

        subject
      end
    end

    context "when in observe mode" do
      before { described_class.mode = :observe }

      it { is_expected.to eq [ max ] }

      it "should not even fetch the stats" do
        expect(described_class::StatsEngine).not_to receive(:get)
      end
    end

    context "when errors arise in .timeouts_for itself", :safely do
      let(:error) { RuntimeError }

      before do
        allow(NetworkResiliency::StatsEngine).to receive(:get).and_raise(error)
      end

      it "warns and falls back to the max timeout" do
        expect { subject }.to output(/ERROR/).to_stderr

        expect(described_class.statsd).to have_received(:increment).with(
          "network_resiliency.error",
          tags: {
            method: :timeouts_for,
            type: error,
          },
        )

        is_expected.to eq [ max ]
      end
    end

    describe "units" do
      subject { timeouts.first }

      it "defaults to milliseconds" do
        is_expected.to be p99
      end

      context "when units are milliseconds" do
        let(:units) { :ms }

        it { is_expected.to be p99 }
      end

      context "when units are seconds" do
        let(:units) { :seconds }

        it { is_expected.to eq 0.02 }

        context "when max is below p99" do
          let(:max) { 0.001 }

          it { is_expected.to eq max }
        end

        context "when no stats are available" do
          let(:stats) { NetworkResiliency::Stats.new }

          it { is_expected.to be max }

          context "when there is no max" do
            let(:max) { nil }

            it { is_expected.to be nil }
          end
        end
      end

      context "when units is invalid" do
        let(:units) { :foo }

        it { expect { timeouts }.to raise_error(ArgumentError) }
      end
    end
  end

  describe ".reset" do
    it "stop syncing" do
      expect(NetworkResiliency::Syncer).to receive(:stop)
      described_class.reset
    end
  end

  describe ".normalize_request" do
    before do
      described_class.normalize_request(:http) do |path|
        path.gsub /oo+/, "oo"
      end

      described_class.normalize_request(:http) do |path|
        path.gsub /_\d+$/, "_x"
      end
    end

    let(:path) { "/fooooo_123" }

    it "normalizes the request" do
      expect(described_class.normalize_request(:http, path)).to eq "/foo_x"
    end

    it "can be cleared" do
      described_class.normalize_request(:http).clear
      expect(described_class.normalize_request(:http, path)).to eq path
    end

    context "when request context is utilized" do
      let(:host) { "example.com" }

      before do
        described_class.normalize_request(:http) do |path, host:|
          if host == "example.com"
            path = "/example"
          end
        end
      end

      it "takes the context into account" do
        res = described_class.normalize_request(:http, path, host: host)
        expect(res).to eq "/example"
      end

      context "when context is specified without a request" do
        it "fails" do
          expect {
            described_class.normalize_request(:http, host: host)
          }.to raise_error(ArgumentError)
        end
      end
    end

    context "when an invalid adapter is specified" do
      it "fails" do
        expect {
          described_class.normalize_request(:foo)
      }.to raise_error(ArgumentError)
      end
    end

    context "when both a request and block are specified" do
      it "fails" do
        expect {
          described_class.normalize_request(:http, path) { nil }
      }.to raise_error(ArgumentError)
      end
    end
  end
end
