describe NetworkResiliency::Adapter::HTTP, :mock_socket do
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
    subject do
      http.connect rescue Net::OpenTimeout

      NetworkResiliency.statsd
    end

    before do
      described_class.patch(http)
    end

    it "logs connection" do
      is_expected.to have_received(:distribution).with(
        /connect/,
        Numeric,
        anything,
      )
    end

    it "logs duration" do
      is_expected.to have_received(:distribution) do |_, duration, _|
        expect(duration).to be > 0
      end
    end

    it "tags the destination host" do
      is_expected.to have_received(:distribution).with(
        String,
        Numeric,
        tags: include(destination: uri.host),
      )
    end

    it "completes request" do
      res = http.get "/"
      expect(res.body).to eq "OK"
      expect(NetworkResiliency.statsd).to have_received(:distribution)
    end

    context "when server connection times out" do
      let(:uri) { URI("http://timeout.com") }

      it "raises an error" do
        expect { http.connect }.to raise_error(Net::OpenTimeout)
      end

      it "logs timeout" do
        is_expected.to have_received(:distribution).with(
          String,
          Numeric,
          tags: include(error: Net::OpenTimeout),
        )
      end
    end

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.disable! }

      it "does not call datadog" do
        is_expected.not_to have_received(:distribution)
      end

      context "when server connection times out" do
        let(:uri) { URI("http://timeout.com") }

        it "raises an error" do
          expect { http.connect }.to raise_error(Net::OpenTimeout)
        end

        it "does not log timeout" do
          is_expected.not_to have_received(:distribution)
        end
      end
    end

    context "when host is a raw IP address" do
      let(:http) { Net::HTTP.new("127.0.0.1") }

      it "does not call datadog" do
        is_expected.not_to have_received(:distribution)
      end
    end
  end
end
