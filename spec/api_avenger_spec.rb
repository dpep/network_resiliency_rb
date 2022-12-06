describe ApiAvenger do
  describe ".time" do
    it "converts to milliseconds and rounds" do
      ts = ApiAvenger.time { sleep 0.001 }

      expect(ts).to be(1).or(eq(2))
    end

    it do
      ts = ApiAvenger.time { sleep 0.01 }

      expect(ts).to be(10).or(eq(11))
    end

    it "has a min of 1 ms" do
      ts = ApiAvenger.time {}
      expect(ts).to be 1
    end
  end
end
