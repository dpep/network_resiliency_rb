describe NetworkResiliency::Adapter::Faraday, :mock_socket do
  let(:faraday) do
    Faraday.new(url: uri.to_s) do |f|
      f.adapter :network_resiliency
    end
  end
  let(:uri) { URI("http://example.com") }

  describe ".connect" do
    subject do
      response rescue Faraday::ConnectionFailed
      NetworkResiliency
    end

    before do
      allow(NetworkResiliency).to receive(:record)
    end

    let(:response) { faraday.get.body }

    it "logs connection" do
      is_expected.to have_received(:record).with(
        adapter: "http",
        action: "connect",
        destination: uri.host,
        duration: be_a(Numeric),
        error: nil,
      )
    end

    it "completes request" do
      expect(response).to eq "OK"
    end

    context "when server connection times out" do
      let(:uri) { URI("http://timeout.com") }

      it "raises an error" do
        expect { response }.to raise_error(Faraday::ConnectionFailed)
      end

      it "logs timeout" do
        is_expected.to have_received(:record).with(
          include(error: Net::OpenTimeout),
        )
      end
    end

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.enabled = false }

      it { is_expected.not_to have_received(:record) }

      context "when server connection times out" do
        let(:uri) { URI("http://timeout.com") }

        it "raises an error" do
          expect { response }.to raise_error(Faraday::ConnectionFailed)
        end

        it "does not log timeout" do
          is_expected.not_to have_received(:record)
        end
      end
    end

    it "patches the Net::HTTP instance" do
      expect(NetworkResiliency::Adapter::HTTP).to receive(:patch) do |obj|
        expect(obj).to be_a Net::HTTP
      end

      response
    end

    context "when Net::HTTP is already patched" do
      before do
        allow(NetworkResiliency::Adapter::HTTP).to receive(:patched?).and_return(true)
      end

      it "does not double patch" do
        expect(NetworkResiliency::Adapter::HTTP).not_to receive(:patch)

        response
      end
    end
  end
end
