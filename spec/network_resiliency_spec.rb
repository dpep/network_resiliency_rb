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
    subject { NetworkResiliency.enabled? }

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
end
