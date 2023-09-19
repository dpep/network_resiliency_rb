describe NetworkResiliency::Adapter::HTTP do
  let(:http) { Net::HTTP.new(uri.host) }
  let(:uri) { URI('http://example.com') }

  describe ".patch" do
    subject { described_class.patched?(http) }

    it { is_expected.to be false }

    context "when patched" do
      before { described_class.patch(http) }

      it { is_expected.to be true }
    end

    it "has not patched globally" do
      expect(described_class.patched?).to be false
    end
  end

  describe ".connect" do
    before do
      described_class.patch(http)
    end

    it "logs connection" do
      expect(NetworkResiliency.statsd).to receive(:distribution).with(
        /connect/,
        Numeric,
        anything,
      )

      http.connect
    end

    it "logs duration" do
      expect(NetworkResiliency.statsd).to receive(:distribution) do |_, duration, _|
        expect(duration).to be > 0
      end

      http.connect
    end

    it "tags the destination host" do
      expect(NetworkResiliency.statsd).to receive(:distribution).with(
        String,
        Numeric,
        tags: include(destination: uri.host),
      )

      http.connect
    end

    it "completes request" do
      expect(NetworkResiliency.statsd).to receive(:distribution)

      res = http.get "/"
      expect(res.body).to eq "OK"
    end

    context "when server connection times out" do
      let(:uri) { URI("http://timeout.com") }

      it "logs timeouts" do
        expect(NetworkResiliency.statsd).to receive(:distribution).with(
          String,
          Numeric,
          tags: include(error: Net::OpenTimeout),
        )

        expect {
          http.connect
        }.to raise_error(Net::OpenTimeout)
      end
    end
  end
end
