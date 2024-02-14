describe NetworkResiliency::Syncer do
  before do
    # mocking not supported in Threads
    NetworkResiliency.statsd = nil

    # unstub from spec_helper
    allow(NetworkResiliency::Syncer).to receive(:start).and_call_original
  end

  def start
    described_class.start
  end

  describe ".start" do
    it "returns a Thread" do
      expect(start).to be_a(Thread)
    end

    it "is idempotent" do
      threads = 3.times.map { start }
      expect(threads.uniq.count).to eq 1
    end

    it "is shared between threads" do
      t = Thread.new { start }

      expect(t.value).to eq start
    end

    context "when worker is stopped" do
      let(:worker) do
        worker = start
        worker.kill
        worker.join
      end

      it "starts a new worker" do
        expect(worker).not_to be_alive
        expect(start).not_to eq worker
      end
    end

    context "when redis is not configured" do
      before { NetworkResiliency.redis = nil }

      it "does not start a worker" do
        expect(start).to be_nil
      end
    end
  end

  describe ".stop" do
    let(:worker) { start }

    it "stops syncing" do
      expect(worker).to be_alive

      described_class.stop

      expect(worker).not_to be_alive
    end
  end

  describe ".syncing?" do
    subject { described_class.syncing? }

    it { is_expected.to be false }

    it "returns true when syncing" do
      start

      is_expected.to be true
    end

    it "returns false when syncing is stopped" do
      start
      described_class.stop

      is_expected.to be false
    end
  end

  describe "#sync" do
    subject(:sync) { worker.send(:sync) }

    let(:worker) do
      worker = start
      worker.kill
      worker.join
    end

    context "when worker encounters an error", :safely do
      before do
        allow(NetworkResiliency::StatsEngine).to receive(:sync).and_raise
      end

      it "logs the error" do
        expect(NetworkResiliency).to receive(:warn)

        sync
      end
    end
  end
end
