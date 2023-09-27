describe NetworkResiliency do
  def expect_enabled
    expect(NetworkResiliency.enabled?(:http))
  end

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
end
