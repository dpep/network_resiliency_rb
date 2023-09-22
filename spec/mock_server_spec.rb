describe "MockServer", :mock_socket do
  let(:uri) { URI("http://example.com/") }

  context "with naked get" do
    subject(:response) { Net::HTTP.get(uri.host, uri.path) }

    it { expect(response).to eq "OK" }
  end

  context "with client" do
    subject(:response) { http.get(uri.path) }

    let(:http) { Net::HTTP.new(uri.host) }

    it { expect(response.code).to eq "200" }
    it { expect(response.body).to eq "OK" }
  end

  context "when GET /timeout" do
    subject(:connect) { Net::HTTP.start("timeout.com") }

    it "times out and raises an exception" do
      expect { connect }.to raise_error(Net::OpenTimeout)
    end
  end
end
