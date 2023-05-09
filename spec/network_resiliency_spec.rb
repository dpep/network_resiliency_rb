describe NetworkResiliency do
  describe ".time" do
    it "converts to milliseconds" do
      ts = NetworkResiliency.time { sleep 0.001 }

      expect(ts).to be_within(1).of(1)
    end

    it do
      ts = NetworkResiliency.time { sleep 0.01 }

      expect(ts).to be_within(1).of(10)
    end

    it "has a min of 1 ms" do
      ts = NetworkResiliency.time {}
      expect(ts).to be_within(1).of(0)
    end
  end
end
