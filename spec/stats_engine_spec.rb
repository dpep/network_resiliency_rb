describe NetworkResiliency::StatsEngine do
  let(:redis) { Redis.new }

  describe ".add" do
    it "accumulates stats" do
      res = described_class.add("foo", 1)
      expect(res).to approximate NetworkResiliency::Stats.new << 1
    end
  end

  describe ".get" do
    it "returns Stats" do
      res = described_class.get("foo")
      expect(res).to be_a(NetworkResiliency::Stats)
      expect(res.n).to be 0
    end

    it "returns accumulated local stats" do
      described_class.add("foo", 1)
      described_class.add("foo", 2)

      res = described_class.get("foo")
      expect(res).to approximate NetworkResiliency::Stats.new << [ 1, 2 ]
    end
  end

  describe ".sync" do
    subject(:sync) { described_class.sync(redis) }

    context "when there are remote stats" do
      before do
        stats = NetworkResiliency::Stats.new << 1
        stats.sync(redis, "foo")
      end

      it "syncs stats to redis" do
        described_class.add("foo", 1)
        res = described_class.get("foo")
        expect(res.n).to be 1

        sync

        res = described_class.get("foo")
        expect(res.n).to be 2
      end

      it "fetches stats that were accessed via get" do
        res = described_class.get("foo")
        expect(res.n).to be 0

        sync

        res = described_class.get("foo")
        expect(res.n).to be 1
      end
    end

    it "combines local and remote stats" do
      described_class.add("foo", 1)

      sync

      described_class.add("foo", 3)

      res = described_class.get("foo")
      expect(res).to approximate NetworkResiliency::Stats.new << [ 1, 3 ]
    end

    it "returns the keys synced" do
      described_class.add("foo", 1)
      described_class.add("bar", 2)

      expect(sync).to eq [ "foo", "bar" ]
    end

    it "is a no-op when there are no local stats" do
      expect(sync).to be_empty
    end

    it "has limits" do
      (described_class::SYNC_LIMIT + 1).times do |i|
        described_class.get(i)
      end

      expect(sync.count).to be described_class::SYNC_LIMIT
    end

    it "prioritizes syncing dirty keys" do
      described_class.add("foo", 1)

      described_class::SYNC_LIMIT.times do |i|
        described_class.get(i)
      end

      expect(sync).to include "foo"
    end

    it "prioritizes syncing stats by usage" do
      (1..described_class::SYNC_LIMIT).each do |i|
        described_class.add(i, 1)
        described_class.add(i, 1)

        described_class.add(-i, 1)
      end

      res = sync.select { |key| key.to_i > 0 }
      expect(res.count).to eq described_class::SYNC_LIMIT
    end

    describe "statsd" do
      subject(:statsd) do
        sync
        NetworkResiliency.statsd
      end

      context "with one key to sync" do
        before { described_class.add("foo", 1) }

        it "logs sync time" do
          is_expected.to have_received(:time).with("network_resiliency.sync")
        end

        it "logs number of keys synced" do
          is_expected.to have_received(:distribution).with(
            "network_resiliency.sync.keys",
            1,
            anything,
          )
        end

        it "logs number of dirty keys" do
          is_expected.to have_received(:distribution).with(
            "network_resiliency.sync.keys.dirty",
            1,
            anything,
          )
        end
      end

      context "when there are too many keys to sync" do
        before do
          described_class.add("foo", 1)

          described_class::SYNC_LIMIT.times do |i|
            described_class.get(i)
          end
        end

        it "differentiates keys to fetch from dirty keys" do
          is_expected.to have_received(:distribution).with(
            "network_resiliency.sync.keys.dirty",
            1,
            anything,
          )
        end

        it "only syncs a limited number of keys" do
          is_expected.to have_received(:distribution).with(
            "network_resiliency.sync.keys",
            described_class::SYNC_LIMIT,
            anything,
          )
        end
      end
    end

    context "when Datadog is not configured" do
      before { NetworkResiliency.statsd = nil }

      it "still syncs stats" do
        described_class.get("foo")
        expect(sync).to eq [ "foo" ]
      end
    end

    describe "concurrency lock" do
      before { described_class.add("foo", 1) }

      it "prevents other threads from concurrently syncing" do
        # only once, since concurrent sync aborts early
        expect(NetworkResiliency.statsd).to receive(:distribution).with(
          "network_resiliency.sync.keys",
          any_args,
        ).once
        expect(NetworkResiliency.statsd).to receive(:distribution).with(
          "network_resiliency.sync.keys.dirty",
          any_args,
        ).once

        expect(NetworkResiliency.statsd).to receive(:time).once do |&block|
          expect(described_class).to be_syncing

          # this should be a no-op
          t = Thread.new { described_class.sync(redis) }
          expect(t.value).to be_empty

          expect(described_class).to be_syncing

          block.call
        end

        expect(sync).to eq [ "foo" ]
      end

      it "is resilient to failures" do
        expect(NetworkResiliency.statsd).to receive(:time).and_raise

        expect { sync }.to raise_error(RuntimeError)

        expect(described_class).not_to be_syncing
      end
    end
  end

  describe ".syncing?" do
    before { described_class.add("foo", 1) }

    it { expect(described_class).not_to be_syncing }

    it "detects syncing" do
      expect(NetworkResiliency.statsd).to receive(:time) do |&block|
        expect(described_class).to be_syncing

        block.call
      end

      described_class.sync(redis)

      expect(described_class).not_to be_syncing
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
