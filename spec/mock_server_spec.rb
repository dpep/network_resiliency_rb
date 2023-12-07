describe "MockServer", :mock_socket do
  let(:uri) { URI("http://example.com/") }

  context "with naked get" do
    subject(:response) { Net::HTTP.get(uri) }

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

  context "when a header is sent" do
    subject(:response) { Net::HTTP.get_response(uri, headers) }

    let(:headers) do
      { "X-Request-Timeout" => "0.001" }
    end

    it { expect(response.body).to eq "OK" }

    it "echos the header" do
      response_headers = response.each_capitalized.to_h
      expect(response_headers).to include headers
    end
  end
end
