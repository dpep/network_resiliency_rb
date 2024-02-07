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

    it "can be called many times without error" do
      3.times { start }
    end

    it "will stop previous workers so only one is running at a time" do
      first_worker = start
      second_worker = start

      expect(first_worker).not_to be_alive
      expect(second_worker).to be_alive
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
end
