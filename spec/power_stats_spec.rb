describe NetworkResiliency::PowerStats do
  subject(:buckets) { described_class.new }

  describe "#n" do
    subject { buckets.n }

    it { is_expected.to be 0 }

    it "tracks a value added" do
      buckets << 1

      is_expected.to be 1
    end

    it "tracks lots of values" do
      i = 100

      i.times.map { |i| buckets << i }

      is_expected.to be i
    end
  end

  describe "#percentile" do
    context "when bucket is empty" do
      it { expect(buckets.n).to be 0}
      it { expect(buckets.percentile(0)).to be 0 }
      it { expect(buckets.percentile(50)).to be 0 }
      it { expect(buckets.percentile(100)).to be 0 }
    end

    it do
      100.times { buckets << 10 }

      expect(buckets.percentile(0)).to be 10
      expect(buckets.percentile(10)).to be 10
      expect(buckets.percentile(90)).to be 10
      expect(buckets.percentile(100)).to be 10
    end

    it do
      5.times { buckets << 1 }
      90.times { buckets << 10 }
      5.times { buckets << 100 }

      expect(buckets.percentile(0)).to be 1
      expect(buckets.percentile(4)).to be 1
      expect(buckets.percentile(5)).to be 10
      expect(buckets.percentile(10)).to be 10
      expect(buckets.percentile(90)).to be 10
      expect(buckets.percentile(95)).to be 100
      expect(buckets.percentile(100)).to be 100
    end

    it "works with 10x the numbers" do
      50.times { buckets << 1 }
      900.times { buckets << 10 }
      50.times { buckets << 100 }

      expect(buckets.percentile(0)).to be 1
      expect(buckets.percentile(4)).to be 1
      expect(buckets.percentile(5)).to be 10
      expect(buckets.percentile(10)).to be 10
      expect(buckets.percentile(90)).to be 10
      expect(buckets.percentile(95)).to be 100
      expect(buckets.percentile(100)).to be 100
    end

    it "normalizes numbers" do
      10.times { buckets << rand }
      expect(buckets.percentile(100)).to be 1

      10.times { buckets << rand(2..10) }
      expect(buckets.percentile(10)).to be 1
      expect(buckets.percentile(50)).to be 10
      expect(buckets.percentile(100)).to be 10
    end

    it "raises an error for invalid percentiles" do
      expect {
        buckets.percentile(-1)
      }.to raise_error(ArgumentError)

      expect {
        buckets.percentile(111)
      }.to raise_error(ArgumentError)
    end
  end

  describe "#p99" do
    it "returns the 99th percentile" do
      99.times { buckets << 1 }
      buckets << 100

      expect(buckets.p99).to be 100
    end
  end

  describe "#merge" do
    it "returns a PowerStats instance" do
      expect(buckets.merge(buckets)).to be_a(described_class)
    end

    it "works with empty buckets" do
      expect(buckets.merge(buckets).n).to be 0
      expect(buckets.merge(buckets).percentile(100)).to be 0
    end

    it "merges two buckets" do
      10.times { buckets << 1 }
      other = described_class.new << 10.times.map { 10 }
      res = buckets.merge(other)

      expect(res.n).to be 20
      expect(res.percentile(0)).to be 1
      expect(res.percentile(10)).to be 1
      expect(res.percentile(50)).to be 10
      expect(res.percentile(100)).to be 10
    end

    it "merges buckets with different sizes" do
      10.times { buckets << 10 }
      10.times { buckets << 100 }

      other = described_class.new << 80.times.map { 1 }
      res = buckets.merge(other)

      expect(res.n).to be 100
      expect(res.percentile(0)).to be 1
      expect(res.percentile(80)).to be 10
      expect(res.percentile(90)).to be 100
    end

    it "does not modify the original" do
      other = described_class.new << 10.times.map { 10 }
      buckets.merge(other)

      expect(buckets.n).to be 0
    end
  end

  describe "#merge!" do
    it "modifies the original" do
      other = described_class.new << 10.times.map { 10 }
      buckets.merge!(other)

      expect(buckets.n).to be 10
    end
  end

  describe "#<<" do
    it "accepts another instance" do
      other = described_class.new
      expect(buckets).to receive(:merge!).with(other)

      buckets << other
    end
  end

  describe "#scale!" do
    it "scales the bucket" do
      10.times { buckets << 1 }
      10.times { buckets << 10 }
      buckets.scale!(50)

      expect(buckets.n).to be 10
      expect(buckets.percentile(1)).to be 1
      expect(buckets.percentile(40)).to be 1
      expect(buckets.percentile(50)).to be 10
      expect(buckets.percentile(100)).to be 10
    end

    it "rounds scaled values" do
      7.times { buckets << 1 }
      buckets.scale!(50)

      expect(buckets.n).to be 4
    end

    it "raises an error for invalid percentages" do
      expect {
        buckets.scale!(-1)
      }.to raise_error(ArgumentError)

      expect {
        buckets.scale!(101)
      }.to raise_error(ArgumentError)
    end
  end

  describe "#reset" do
    it "resets the bucket" do
      10.times { buckets << 10 }
      buckets.reset

      expect(buckets.n).to be 0
      expect(buckets.percentile(100)).to be 0
    end
  end

  describe ".[]" do
    it "creates new instances on demand" do
      expect(described_class[:foo]).to be_a(described_class)
      expect(described_class[:foo]).not_to be described_class[:bar]
    end
  end

  describe ".reset" do
    it "resets all instances" do
      obj = described_class[:foo]
      described_class.reset

      expect(described_class[:foo]).not_to be obj
    end
  end
end
