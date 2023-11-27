describe NetworkResiliency::Syncer do
  before do
    # mocking not supported in Threads
    NetworkResiliency.statsd = nil

    # unstub from spec_helper
    allow(NetworkResiliency::Syncer).to receive(:start).and_call_original
  end

  let(:redis) { Redis.new }

  def start
    described_class.start(redis)
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

      first_worker.join

      expect(first_worker).not_to be_alive
      expect(second_worker).to be_alive
    end
  end

  describe ".stop" do
    it "stops syncing" do
      worker = start
      expect(worker).to be_alive

      described_class.stop

      worker.join
      expect(worker).not_to be_alive
    end
  end
end
