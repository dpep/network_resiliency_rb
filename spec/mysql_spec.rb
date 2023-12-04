describe NetworkResiliency::Adapter::Mysql, :mock_mysql do
  describe ".patch" do
    subject do
      described_class.patched?
    end

    it { is_expected.to be false }

    context "when patched" do
      before do
        allow(Mysql2::Client).to receive(:prepend).and_call_original
        described_class.patch
      end

      it { is_expected.to be true }

      it "will only patch once" do
        described_class.patch
        described_class.patch

        expect(Mysql2::Client).to have_received(:prepend).once
      end
    end
  end

  describe ".connect" do
    subject do
      mysql rescue Mysql2::Error::ConnectionError

      NetworkResiliency
    end

    let(:host) { "my.fav.sql.com" }
    let(:mysql) do
      Mysql2::Client.new(host: host, socket: mock_mysql, connect_timeout: timeout)
    end
    let(:timeout) { 60 }
    # let(:select) { mysql.query("SELECT 1").first.first.last }

    before do
      described_class.patch
      allow(NetworkResiliency).to receive(:record).and_call_original
    end

    it "can not connect to a mysql server" do
      expect { mysql }.to raise_error(Mysql2::Error::ConnectionError)
    end

    it "logs connection" do
      is_expected.to have_received(:record).with(
        adapter: "mysql",
        action: "connect",
        destination: host,
        duration: be_a(Integer),
        error: nil,
        timeout: be_a(Numeric),
      )
    end

    it "logs timeout" do
      subject

      expect(NetworkResiliency.statsd).to have_received(:gauge).with(
        "network_resiliency.connect.timeout",
        timeout * 1_000,
        anything,
      )
    end

    context "when connect timeout is nil" do
      let(:timeout) { nil }

      it "does not log timeout" do
        subject

        expect(NetworkResiliency.statsd).not_to have_received(:gauge)
      end
    end

    context "when server connection times out" do
      before do
        Mysql2::Client.class_eval do
          def connect(...)
            raise Mysql2::Error::TimeoutError.new("fake timeout", nil, error_number = 1205)
          end
        end
      end

      it "raises an error" do
        expect { mysql }.to raise_error(Mysql2::Error::TimeoutError)
      end

      it "logs timeout" do
        is_expected.to have_received(:record).with(
          include(error: Mysql2::Error::TimeoutError),
        )
      end
    end
  end
end
