describe NetworkResiliency::StatsEngine do
  let(:redis) { Redis.new }

  describe ".add" do
    it "accumulates stats" do
      described_class.add("foo", 1)
    end
  end

  describe ".get" do
    it "returns accumulated stats" do
      described_class.add("foo", 1)

      res = described_class.get("foo")
      expect(res).to be_a(NetworkResiliency::Stats)
      expect(res).to approximate NetworkResiliency::Stats.new << 1
    end

    it "combines local and remote stats" do
      described_class.add("foo", 1)
      described_class.sync(redis, [ "foo" ])

      described_class.add("foo", 3)

      res = described_class.get("foo")
      expect(res).to approximate NetworkResiliency::Stats.new << [ 1, 3 ]
    end
  end

  describe ".sync" do
    context "when there are remote stats" do
      before do
        described_class.add("foo", 1)
        described_class.sync(redis, [ "foo" ])
        described_class.reset
      end

      it "syncs stats to redis" do
        described_class.add("foo", 1)
        res = described_class.get("foo")
        expect(res.n).to be 1

        described_class.sync(redis, [ "foo" ])
        res = described_class.get("foo")
        expect(res.n).to be 2
      end
    end
  end

  describe ".reset" do
    it "resets stats" do
      described_class.add("foo", 1)
      described_class.reset

      res = described_class.get("foo")
      expect(res.n).to be 0
    end
  end
end
