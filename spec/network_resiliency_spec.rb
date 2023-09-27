describe NetworkResiliency do
  describe ".timestamp" do
    before do
      allow(Process).to receive(:clock_gettime).and_return(1, 2)
    end

    it "converts to milliseconds" do
      ts = -NetworkResiliency.timestamp
      ts += NetworkResiliency.timestamp

      expect(ts).to be 1_000
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
      before do
        NetworkResiliency.enabled = proc { true }
      end

      it { is_expected.to be true }
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

    def is_expected
      expect(NetworkResiliency.enabled?(:http))
    end

    it "enables" do
      NetworkResiliency.enable!
      is_expected.to be true
    end

    it "resets after the given block" do
      NetworkResiliency.enable! do
        is_expected.to be true
      end

      is_expected.to be false
    end
  end

  describe ".disable!" do
    before { NetworkResiliency.enabled = true }

    def is_expected
      expect(NetworkResiliency.enabled?(:http))
    end

    it "disables" do
      NetworkResiliency.disable!
      is_expected.to be false
    end

    it "resets after the given block" do
      NetworkResiliency.disable! do
        is_expected.to be false
      end

      is_expected.to be true
    end
  end

  describe ".configure" do
    it "yields a config object" do
      expect {|b| NetworkResiliency.configure(&b) }.to yield_control
    end

    it "configures NetworkResiliency" do
      expect(NetworkResiliency.enabled?(:http)).to be true

      NetworkResiliency.configure do |conf|
        conf.enabled = false
      end

      expect(NetworkResiliency.enabled?(:http)).to be false
    end
  end
end
