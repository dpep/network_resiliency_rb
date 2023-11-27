describe NetworkResiliency::Adapter::HTTP, :mock_socket do
  let(:http) { Net::HTTP.new(uri.host) }
  let(:uri) { URI('http://example.com/') }

  before do
    allow(NetworkResiliency).to receive(:record)
  end

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

        expect(Timeout).to receive(:timeout) do
          expect(http.connect_timeout).to eq timeouts.first
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

  describe ".request" do
    subject(:body) do
      http.request(request).body rescue Net::ReadTimeout
    end

    let(:request) { Net::HTTP::Get.new(uri.path) }

    before do
      described_class.patch(http)
    end

    it "logs connection" do
      body

      expect(NetworkResiliency).to have_received(:record).with(
        adapter: "http",
        action: "request",
        destination: "get:#{uri.host}:#{uri.path}",
        duration: be_a(Integer),
        error: nil,
        timeout: be_a(Numeric),
        attempts: be_an(Integer),
      )
    end

    it "completes request" do
      is_expected.to eq "OK"
    end

    describe "resilient mode" do
      before do
        NetworkResiliency.mode = :resilient

        allow(NetworkResiliency).to receive(:timeouts_for) { timeouts.dup }
      end

      let(:default_timeout) { http.read_timeout }
      let(:timeouts) { [ 1, 0.010 ].freeze }

      it { expect(http.read_timeout).to eq default_timeout }
      it { expect(timeouts.first).not_to eq default_timeout }

      it "dynamically adjusts the timeout" do
        expect(request).to receive(:exec).and_call_original do
          expect(http.read_timeout).to eq timeouts.first
        end

        body
      end

      it "restores the original timeout" do
        body

        expect(http.read_timeout).to eq default_timeout
      end

      it "dynamically adjusts max_retries" do
        http.max_retries = 2

        expect(request).to receive(:exec).and_call_original do
          expect(http.max_retries).to eq 0
        end

        body

        expect(http.max_retries).to eq 2
      end

      context "when server connection times out" do
        before do
          allow(request).to receive(:exec).and_raise(Net::ReadTimeout)
        end

        it "retries" do
          body
          expect(request).to have_received(:exec).twice
        end

        it "retries with a separate connection" do
          expect(http).to receive(:connect).twice.and_call_original

          body
        end

        context "when request is not idepotent" do
          let(:request) { Net::HTTP::Post.new(uri.path) }

          it "does not retry" do
            subject

            expect(request).to have_received(:exec).once
          end

          it "uses the most lenient timeout" do
            expect(request).to receive(:exec).and_call_original do
              expect(http.read_timeout).to eq timeouts.last
            end

            subject
          end
        end
      end

      context "when server connects on the second attempt" do
        before do
          allow(request).to receive(:exec).and_wrap_original do |original, *args|
            if @attempted.nil?
              @attempted = true
              raise Net::ReadTimeout
            end

            original.call(*args)
          end

          body
        end

        it "retries" do
          expect(request).to have_received(:exec).twice
        end

        it { is_expected.to eq "OK" }

        it "logs" do
          expect(NetworkResiliency).to have_received(:record).with(
            include(
              error: nil,
              attempts: 2,
            ),
          )
        end
      end
    end

    context "when NetworkResiliency is disabled" do
      before { NetworkResiliency.disable! }

      it { is_expected.to eq "OK" }
      it { expect(NetworkResiliency).not_to have_received(:record) }
    end
  end

  describe ".normalize_path" do
    using NetworkResiliency::Adapter::HTTP

    subject { http.normalize_path(path) }

    context "when path is /" do
      let(:path) { "/" }

      it { is_expected.to eq "/" }
    end

    context "when path is /foo" do
      let(:path) { "/foo" }

      it { is_expected.to eq "/foo" }
    end

    context "when path contains an id" do
      let(:path) { "/foo/123" }

      it { is_expected.to eq "/foo/x" }
    end

    context "when path contains a uuid" do
      let(:path) { "/foo/12345678-1234-1234-1234-123456789012/bar" }

      it { is_expected.to eq "/foo/x/bar" }
    end

    context "when path contains duplicate slashes" do
      let(:path) { "//foo///123" }

      it { is_expected.to eq "/foo/x" }
    end

    context "when NetworkResiliency configured with custom normalization" do
      before do
        NetworkResiliency.configure do |c|
          c.normalize_request(:http) do |path|
            path.sub "foo", "bar"
          end
        end
      end

      let(:path) { "/foo/123" }

      it { is_expected.to eq "/bar/x" }
    end
  end
end
