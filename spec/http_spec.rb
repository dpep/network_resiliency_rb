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

    it "patches globally" do
      stub_const("Net::HTTP", Class.new(Net::HTTP))

      described_class.patch

      described_class.patched?
    end

    it "does not double patch" do
      expect(http.singleton_class).to receive(:prepend).once.and_call_original

      described_class.patch(http)
      described_class.patch(http)
    end
  end

  describe ".connect" do
    subject do
      http.connect rescue Net::OpenTimeout

      NetworkResiliency
    end

    let(:body) { http.get("/").body }

    before do
      described_class.patch(http)
      allow(NetworkResiliency).to receive(:record)
    end

    it "logs connection" do
      is_expected.to have_received(:record).with(
        adapter: "http",
        action: "connect",
        destination: uri.host,
        duration: be_a(Integer),
        error: nil,
        timeout: be_a(Numeric),
        attempts: be_an(Integer),
      )
    end

    it "completes request" do
      expect(body).to eq "OK"
    end

    context "when server connection times out" do
      let(:uri) { URI("http://timeout.com") }

      it "raises an error" do
        expect { http.connect }.to raise_error(Net::OpenTimeout)
      end

      it "logs timeout" do
        is_expected.to have_received(:record).with(
          include(error: Net::OpenTimeout),
        )
      end
    end

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.disable! }

      it { is_expected.not_to have_received(:record) }

      context "when server connection times out" do
        let(:uri) { URI("http://timeout.com") }

        it "raises an error" do
          expect { http.connect }.to raise_error(Net::OpenTimeout)
        end

        it "does not log timeout" do
          is_expected.not_to have_received(:record)
        end
      end
    end

    describe "resilient mode" do
      before do
        NetworkResiliency.mode = :resilient

        allow(NetworkResiliency).to receive(:timeouts_for) { timeouts.dup }
      end

      let(:default_timeout) { http.open_timeout }
      let(:timeouts) { [ 10, 100 ].freeze }

      it "completes request" do
        expect(body).to eq "OK"
      end

      it { expect(timeouts.first).not_to eq default_timeout }

      it "dynamically adjusts the timeout" do
        expect(http.open_timeout).to eq default_timeout

        expect(Timeout).to receive(:timeout) do |timeout, _|
          expect(timeout).to eq timeouts.first
        end

        subject
      end

      it "restores the original timeout" do
        subject

        expect(http.open_timeout).to eq default_timeout
      end

      context "when server connection times out" do
        let(:uri) { URI("http://timeout.com") }

        it "retries" do
          expect(TCPSocket).to receive(:open).twice
          subject
        end
      end
    end
  end
end
