describe NetworkResiliency::Adapter::Mysql, :mock_mysql do
  before do
    stub_const("Mysql2::Client", klass_mock)
  end

  let(:klass_mock) { Class.new(Mysql2::Client) }

  describe ".patch" do
    subject do
      described_class.patched?
    end

    it { is_expected.to be false }

    context "when patched" do
      before do
        allow(klass_mock).to receive(:prepend).and_call_original
        described_class.patch
      end

      it { is_expected.to be true }

      it "will only patch once" do
        expect(klass_mock).to have_received(:prepend).once

        described_class.patch

        expect(klass_mock).to have_received(:prepend).once
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
      allow(NetworkResiliency).to receive(:record)
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
        timeout: be_a(Integer),
      )
    end

    context "when server connection times out" do
      let(:klass_mock) do
        Class.new(Mysql2::Client) do
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
