describe NetworkResiliency::Adapter::Faraday, :mock_socket do
  let(:faraday) do
    Faraday.new(url: uri.to_s) do |f|
      f.request :network_resiliency
    end
  end
  let(:uri) { URI("http://example.com") }

  describe ".patch" do
    subject { described_class.patched?(faraday) }

    it { is_expected.to be true }
  end

  describe ".connect" do
    subject(:response) { faraday.get.body }

    it "logs connection" do
      expect(NetworkResiliency.statsd).to receive(:distribution).with(
        /connect/,
        Numeric,
        tags: include(adapter: "faraday"),
      )

      response
    end

    it "logs duration" do
      expect(NetworkResiliency.statsd).to receive(:distribution) do |_, duration, _|
        expect(duration).to be > 0
      end

      response
    end

    it "tags the destination host" do
      expect(NetworkResiliency.statsd).to receive(:distribution).with(
        String,
        Numeric,
        tags: include(destination: uri.host),
      )

      response
    end

    it "completes request" do
      expect(NetworkResiliency.statsd).to receive(:distribution)

      expect(response).to eq "OK"
    end

    it "does not log http adapter also" do
      expect(NetworkResiliency.statsd).to receive(:distribution).once

      response
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
          faraday.get
        }.to raise_error(Faraday::ConnectionFailed)
      end
    end

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.enabled = false }

      it "does not call datadog" do
        expect(NetworkResiliency.statsd).not_to receive(:distribution)

        faraday.get
      end

      context "when server connection times out" do
        let(:uri) { URI("http://timeout.com") }

        it "does not log timeouts" do
          expect(NetworkResiliency.statsd).not_to receive(:distribution)

          expect {
            faraday.get
          }.to raise_error(Faraday::ConnectionFailed)
        end
      end
    end
  end
end
