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
        let(:callback) { proc { raise } }

        it "warns and falls back to observe" do
          expect(described_class).to receive(:warn).with(:mode, Exception)
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
      record

      NetworkResiliency.statsd
    end

    let(:action) { :connect }
    let(:error) { nil }
    let(:duration) { 8 }
    let(:host) { "example.com" }
    let(:timeout) { 100 }
    let(:attempts) { 1 }

    def record
      NetworkResiliency.record(
        adapter: "adapter",
        action: action,
        destination: host,
        duration: duration,
        error: error,
        timeout: timeout,
        attempts: attempts,
      )
    end

    it "records the event" do
      expect { subject }.to change { NetworkResiliency::StatsEngine::STATS.count }.by(1)
    end

    context "when there are many many events" do
      before do
        (NetworkResiliency::RESILIENCY_THRESHOLD * 10).times { record }
      end

      let(:stats) do
        key = NetworkResiliency::StatsEngine::STATS.keys.first
        NetworkResiliency::StatsEngine.get(key)
      end

      it "downsamples" do
        expect(stats.n).to be > NetworkResiliency::RESILIENCY_THRESHOLD
        expect(stats.n).to be < NetworkResiliency::RESILIENCY_THRESHOLD * 10
      end
    end

    it "captures metric info" do
      is_expected.to have_received(:distribution).with(
        "network_resiliency.#{action}",
        duration,
        tags: include(destination: host),
      )

      is_expected.to have_received(:distribution).with(
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
        anything,
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
        is_expected.not_to have_received(:distribution).with(
          "network_resiliency.#{action}.timeout",
          any_args,
        )
      end
    end

    context "when timeout is 0" do
      let(:timeout) { 0 }

      it "does not track timeout" do
        is_expected.not_to have_received(:distribution).with(
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
        expect(described_class).to receive(:warn).with(:record, Exception)
        subject
      end
    end

    context "when Datadog is not configured" do
      before { NetworkResiliency.statsd = nil }

      it "still works" do
        expect(NetworkResiliency::StatsEngine).to receive(:add).and_call_original
        subject
      end

      context "when errors arise in safe mode", :safely do
        before do
          allow(NetworkResiliency::StatsEngine).to receive(:add).and_raise
        end

        it "warns, but doesn't explode" do
          expect(described_class).to receive(:warn).with(:record, Exception)
          subject
        end
      end
    end

    context "with a deadline" do
      it "logs deadlines that were exceeded" do
        described_class.deadline = Time.now

        is_expected.to have_received(:distribution).with(
          "network_resiliency.#{action}",
          duration,
          tags: include(deadline_exceeded: true),
        )
      end

      it "logs deadlines that were not exceeded" do
        described_class.deadline = Time.now + 1

        is_expected.to have_received(:distribution).with(
          "network_resiliency.#{action}",
          duration,
          tags: include(deadline_exceeded: false),
        )
      end
    end

    context "when there is no deadline" do
      it "does not log deadline metric" do
        is_expected.to have_received(:distribution).with(
          "network_resiliency.#{action}",
          duration,
          tags: hash_not_including(:deadline_exceeded),
        )
      end
    end

    it "will start sync worker" do
      subject
      expect(NetworkResiliency::Syncer).to have_received(:start)
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
        avg: 6,
        stdev: 1,
      )
    end
    let(:n) { described_class::RESILIENCY_THRESHOLD }
    let(:p99) { 10 }
    let(:max) { 1_000 }
    let(:units) { nil }
    let(:timeout_min) { 0 }

    before do
      allow(described_class::StatsEngine).to receive(:get).and_return(stats)
      described_class.mode = :resilient
      described_class.timeout_min = timeout_min
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
      let(:n) { described_class::RESILIENCY_THRESHOLD - 1 }

      it { is_expected.to eq [ max ] }
    end

    context "when n is large" do
      let(:n) { described_class::RESILIENCY_THRESHOLD * 3 }
      let(:p99) { 9 }

      it "generates more granular timeouts" do
        is_expected.to eq [ p99, p99 * 100 ]
      end
    end

    context "when there is no max timeout" do
      let(:max) { nil }

      it "should make two attempts with timeouts" do
        is_expected.to eq [ p99, p99 * 100 ]
      end
    end

    context "when the max timeout is less than the expected p99" do
      let(:max) { p99 / 2 }

      it "only makes one attempt, with the max" do
        is_expected.to eq [ max ]
      end

      it "logs the event" do
        expect(NetworkResiliency.statsd).to receive(:distribution).with(
          "network_resiliency.connect.timeout.dynamic",
          max,
          anything,
        )

        expect(NetworkResiliency.statsd).to receive(:increment).with(
          "network_resiliency.timeout.too_low",
          anything,
        )

        subject
      end
    end

    context "when the max timeout is similarly sized to the p99" do
      let(:max) { p99 * 10 }

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

    context "when timeout_min comes into play" do
      let(:timeout_min) { 50 }

      it "falls back to the timeout_min" do
        is_expected.to eq [ described_class.timeout_min, max - timeout_min ]
      end
    end

    it "logs the dynamic timeout" do
      expect(NetworkResiliency.statsd).to receive(:distribution).with(
        "network_resiliency.connect.timeout.dynamic",
        p99,
        anything,
      )

      subject
    end

    context "when in observe mode" do
      before { described_class.mode = :observe }

      it { is_expected.to eq [ max ] }

      it "should not even fetch the stats" do
        expect(described_class::StatsEngine).not_to receive(:get)
      end
    end

    context "when errors arise in .timeouts_for itself", :safely do
      before do
        allow(NetworkResiliency::StatsEngine).to receive(:get).and_raise
      end

      it "warns and falls back to the max timeout" do
        expect(described_class).to receive(:warn).with(:timeouts_for, Exception)
        is_expected.to eq [ max ]
      end
    end

    describe "units" do
      subject { timeouts.first }

      it "defaults to milliseconds" do
        is_expected.to eq p99
      end

      context "when units are milliseconds" do
        let(:units) { :ms }

        it { is_expected.to eq p99 }
      end

      context "when units are seconds" do
        let(:units) { :seconds }

        it { is_expected.to eq 0.01 }
        it { is_expected.to eq p99.to_f / 1_000 }

        context "when max is below p99" do
          let(:max) { 0.001 }

          specify { expect(max).to be < p99 }

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
    before { allow(NetworkResiliency::Syncer).to receive(:stop) }

    it "stop syncing" do
      described_class.reset

      expect(NetworkResiliency::Syncer).to have_received(:stop)
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

  describe ".warn", :safely do
    subject { described_class.warn(method_name, error) }

    let(:method_name) { :my_method }
    let(:error) { Redis::CannotConnectError.new("nope") }

    it "logs a warning and sends Datadog metrics" do
      expect(NetworkResiliency.statsd).to receive(:increment).with(
        "network_resiliency.error",
        tags: { method: method_name, type: error.class },
      )

      expect { subject }.to output(
        /NetworkResiliency #{method_name}: #{error.class}: #{error.message}/,
      ).to_stderr
    end
  end

  describe ".timeout_min" do
    subject { described_class.timeout_min }

    it "has a default" do
      is_expected.to eq described_class::DEFAULT_TIMEOUT_MIN
    end

    context "when set" do
      before { described_class.timeout_min = timeout }

      let(:timeout) { 1_000 }

      it { is_expected.to eq timeout }
    end

    context "when set to a bogus value" do
      it "fails fast" do
        expect {
          described_class.timeout_min = "foo"
        }.to raise_error(ArgumentError)
      end
    end
  end
end
