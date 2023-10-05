describe NetworkResiliency::Adapter::Postgres do
  before do
    stub_const("PG::Connection", klass_mock)
  end

  let(:klass_mock) { Class.new(PG::Connection) }

  describe ".patch" do
    subject do
      described_class.patched?
    end

    it { is_expected.to be false }

    context "when patched" do
      before do
        allow(klass_mock.singleton_class).to receive(:prepend).and_call_original
        described_class.patch
      end

      it { is_expected.to be true }

      it "will only patch once" do
        expect(klass_mock.singleton_class).to have_received(:prepend).once

        described_class.patch

        expect(klass_mock.singleton_class).to have_received(:prepend).once
      end
    end
  end

  describe ".connect" do
    subject do
      pg rescue PG::Error

      NetworkResiliency.statsd
    end

    let(:host) { "localhost" }
    let(:pg) { PG.connect(host: host, user: "postgres") }
    let(:select) { pg.query("SELECT 1").first.first.last }

    before do
      described_class.patch
    end

    # fit { byebug }

    it "can not connect to a mysql server" do
      expect { pg }.to raise_error(PG::Error)
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
        tags: include(destination: host),
      )
    end

    context "when server connection times out" do
      let(:klass_mock) do
        Class.new(PG::Connection) do
          def self.connect_start(...)
            raise PG::Error.new
          end
        end
      end

      it "raises an error" do
        expect { pg }.to raise_error(PG::Error)
      end

      it "logs timeout" do
        is_expected.to have_received(:distribution).with(
          String,
          Numeric,
          tags: include(error: PG::Error),
        )
      end
    end
  end
end
