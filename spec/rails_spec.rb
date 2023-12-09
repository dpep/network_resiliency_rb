describe NetworkResiliency::Adapter::Rails, :rails do
  describe ".patch" do
    subject { described_class.patched?(app) }

    let(:app) { Rails.application }

    it { is_expected.to be false }

    context "when patched" do
      before { described_class.patch(app) }

      it { is_expected.to be true }
    end

    context "when patching a bogus object" do
      it "fails fast" do
        expect {
          described_class.patch(double)
        }.to raise_error(ArgumentError, /expected Rails/)
      end
    end
  end

  describe described_class::Middleware do
    subject { get "/" }

    let(:app) do
      Rack::Builder.new do
        use Rack::Lint
        use NetworkResiliency::Adapter::Rails::Middleware

        run (lambda do |env|
          [200, { "content-type" => "application/text" }, ["OK"]]
        end)
      end
    end
    let(:timeout) { 0.01 }

    before do
      header NetworkResiliency::Adapter::HTTP::REQUEST_TIMEOUT_HEADER, timeout.to_s
    end

    it { is_expected.to be_ok }

    it "sets the deadline" do
      allow(NetworkResiliency).to receive(:deadline=)
      subject

      expect(NetworkResiliency).to have_received(:deadline=).with(timeout)
    end

    it "clears the deadline after each request" do
      subject

      expect(NetworkResiliency.deadline).to be_nil
    end
  end
end
