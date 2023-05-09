describe ApiAvenger do
  describe ".time" do
    it "converts to milliseconds" do
      ts = ApiAvenger.time { sleep 0.001 }

      expect(ts).to be_within(1).of(1)
    end

    it do
      ts = ApiAvenger.time { sleep 0.01 }

      expect(ts).to be_within(1).of(10)
    end

    it "has a min of 1 ms" do
      ts = ApiAvenger.time {}
      expect(ts).to be_within(1).of(0)
    end
  end
end
