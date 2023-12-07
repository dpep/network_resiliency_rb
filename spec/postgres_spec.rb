describe NetworkResiliency::Adapter::Postgres do
  describe ".patch" do
    subject do
      described_class.patched?
    end

    it { is_expected.to be false }

    context "when patched" do
      before do
        allow(PG::Connection.singleton_class).to receive(:prepend).and_call_original
        described_class.patch
      end

      it { is_expected.to be true }

      it "will only patch once" do
        described_class.patch
        described_class.patch

        expect(PG::Connection.singleton_class).to have_received(:prepend).once
      end
    end
  end

  describe ".connect" do
    subject do
      pg rescue PG::Error

      NetworkResiliency
    end

    let(:host) { "localhost" }
    let(:pg) do
      PG.connect(host: host, user: "postgres", connect_timeout: timeout)
    end
    let(:timeout) { 60 }
    # let(:select) { pg.query("SELECT 1").first.first.last }

    before do
      described_class.patch
      allow(NetworkResiliency).to receive(:record)
    end

    it "can not connect to a mysql server" do
      expect { pg }.to raise_error(PG::Error)
    end

    it "logs connection" do
      is_expected.to have_received(:record).with(
        adapter: :postgres,
        action: :connect,
        destination: host,
        duration: be_a(Integer),
        error: nil,
        timeout: be_a(Numeric),
      )
    end

    context "when server connection times out" do
      before do
        PG::Connection.class_eval do
          def self.connect_start(...)
            raise PG::Error.new
          end
        end
      end

      it "raises an error" do
        expect { pg }.to raise_error(PG::Error)
      end

      it "logs timeout" do
        is_expected.to have_received(:record).with(
          include(error: PG::Error),
        )
      end
    end
  end
end
