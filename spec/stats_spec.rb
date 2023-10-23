require "network_resiliency/stats"

describe NetworkResiliency::Stats do
  subject(:stats) { described_class.new }

  let(:precision) { 0.00001 }
  let(:data) { [] }

  def calc_avg
    data.flatten!
    data.sum(0.0) / data.count
  end

  def calc_stdev
    avg = calc_avg
    sq_diff = data.sum(0.0) { |x| (x - avg) ** 2 }
    Math.sqrt(sq_diff / data.count)
  end

  def choose(limit: 100_000)
    # rand(-100_000..100_000)
    rand * limit * 2 - limit
  end

  describe 'helper methods' do
    specify 'sanity check' do
      data << [ 1, 2, 3, 4, 5 ]

      expect(calc_avg).to eq 3
      expect(calc_stdev).to eq(Math.sqrt(2))
    end

    specify 'another sanity check' do
      data << (1..31).to_a

      expect(calc_avg).to eq 16
      expect(calc_stdev).to be_within(precision).of(8.94427)
    end

    specify 'yet another' do
      data << [ 10, 12, 23, 23, 16, 23, 21, 16 ]

      expect(calc_avg).to eq 18
      expect(calc_stdev).to be_within(precision).of(4.898979)
    end
  end

  describe '#n' do
    subject { stats.n }

    it 'starts at 0' do
      is_expected.to eq 0
    end

    it 'accumulates correctly' do
      1_000.times do |i|
        stats << 0

        expect(stats.n).to be (i + 1)
      end

      is_expected.to be 1_000
    end
  end

  describe '#avg' do
    subject { stats.avg }

    it 'starts at 0' do
      is_expected.to eq 0
    end

    it do
      1_000.times do |i|
        stats << 3

        expect(stats.avg).to eq 3
      end

      is_expected.to eq 3
    end

    def check
      expect(stats.avg).to be_within(precision).of(calc_avg)
    end

    it do
      1_000.times do |i|
        data << i
        stats << i

        check
      end
    end

    it 'works with random numbers' do
      1_000.times.map { choose }.each do |x|
        data << x
        stats << x

        check
      end

      expect(stats.n).to eq 1_000
    end
  end

  describe '#stdev' do
    subject { stats.stdev }

    it 'starts at 0' do
      is_expected.to eq 0
    end

    it do
      1_000.times do |i|
        stats << 3

        expect(stats.stdev).to eq 0
      end

      is_expected.to eq 0
    end

    def check
      expect(stats.stdev).to be_within(precision).of(calc_stdev)
    end

    it do
      1_000.times do |i|
        data << i
        stats << i

        check
      end
    end

    it 'works with random numbers' do
      1_000.times.map { choose }.each do |x|
        data << x
        stats << x

        check
      end

      expect(stats.n).to eq 1_000
    end
  end

  describe '#<<' do
    def check
      data.flatten!
      expect(stats.n).to eq data.count
      expect(stats.avg).to be_within(precision).of(calc_avg)
      expect(stats.stdev).to be_within(precision).of(calc_stdev)
    end

    it 'calculates the running average and stdev' do
      1_000.times.map { choose }.each do |x|
        data << x
        stats << x

        check
      end
    end

    it 'works with floats also' do
      1_000.times.map { rand * 200 - 100 }.each do |x|
        data << x
        stats << x

        check
      end
    end

    it 'accepts an array of values' do
      values = (1..100).to_a

      data << values
      stats << values

      check
    end

    it 'accepts another Stats object' do
      stats << 1
      stats << 2

      more_stats = described_class.new << [ 3, 4, 5 ]

      expect(stats).to receive(:merge!).with(more_stats).and_call_original
      stats << more_stats

      data << [ 1, 2, 3, 4, 5 ]

      check
    end

    it "catches bogus input" do
      expect {
        stats << Object
      }.to raise_error(ArgumentError)
    end
  end

  describe '#==' do
    it "equals itself" do
      expect(stats).to eq(stats)
    end

    it "equals another empty Stats object" do
      is_expected.to eq(described_class.new)
    end

    it "equals another Stats object with the same data" do
      data = [ 1, 2, 3 ]
      stats << data

      is_expected.to eq(described_class.new << data)
    end

    it "does not equal another Stats object with different data" do
      is_expected.not_to eq(described_class.new << [ 1, 2, 3 ])
    end

    it "does not equal other objects" do
      is_expected.not_to eq(0)
      is_expected.not_to eq(Object.new)
    end
  end

  describe '#merge' do
    subject(:merged_stats) { stats.merge(more_stats) }

    let(:more_stats) { described_class.new << [ 1, 2, 3 ] }

    it "is aliased to '+'" do
      expect(stats.method(:merge)).to eq(stats.method(:+))

      is_expected.to eq(stats + more_stats)
    end

    it "is non-destructive" do
      is_expected.to be_a(described_class)
      is_expected.not_to eq stats

      expect(stats.n).to eq 0
      expect(more_stats.n).to eq 3
    end

    it "calculates stats correctly" do
      expect(merged_stats).to eq more_stats
      expect(merged_stats).not_to be more_stats
    end

    context "when merging an empty Stats object" do
      let(:more_stats) { described_class.new }

      it "calculates stats correctly" do
        expect(merged_stats.n).to eq 0
        expect(merged_stats.avg).to eq 0
        expect(merged_stats.stdev).to eq 0

        stats << [ 1, 2, 3 ]
        expect(stats.merge(described_class.new)).to eq stats
      end
    end

    it "works when merging lots of individual stats" do
      stats = described_class.new

      (1..100).each do |i|
        more_stats = described_class.new << i
        stats = stats.merge(more_stats)
        data << i

        expect(stats.n).to eq data.count
        expect(stats.avg).to be_within(precision).of(calc_avg)
        expect(stats.stdev).to be_within(precision).of(calc_stdev)
      end
    end
  end

  describe '#merge!' do
    subject(:merged_stats) { stats.merge!(more_stats) }

    let(:more_stats) { described_class.new << [ 1, 2, 3 ] }

    it "is destructive" do
      is_expected.to be stats
    end

    it "calculates stats correctly" do
      is_expected.to eq more_stats
      is_expected.not_to be more_stats
    end
  end

  describe "#variance" do
    before { stats << 1_000.times.map { choose } }

    it { expect(Math.sqrt(stats.variance)).to eq(stats.stdev) }

    describe "of a sample" do
      it { expect(stats.variance(sample: true)).to be > stats.variance }
    end
  end

  describe ".from" do
    subject do
      described_class.from(
        n: stats.n,
        avg: stats.avg,
        sq_dist: stats.instance_variable_get(:@sq_dist)
      )
    end

    it { is_expected.to eq stats }
    it { is_expected.not_to be stats }

    context "when stats has data" do
      let(:stats) { described_class.new << [ 1, 2, 3, 4, 5 ] }

      it { is_expected.to eq stats }
    end
  end

  it "works with lots of random numbers" do
    1_000.times do |i|
      values = rand(10..1_000).times.map { choose }

      data << values
      stats << described_class.new(values)

      if i % 100 == 0
        data.flatten!
        expect(stats.n).to eq data.count
        expect(stats.avg).to be_within(precision).of(calc_avg)
        expect(stats.stdev).to be_within(precision).of(calc_stdev)
      end
    end

    expect(stats.n).to be >= 10_000
  end

  # too slow to run regularly, but works with 100M data points
  # it 'works with LOTS of random numbers' do
  #   1_000_000.times do |i|
  #     values = rand(10..1_000).times.map { choose }

  #     data << values
  #     stats << described_class.new(values)

  #     if i % 10_000 == 0
  #       puts "[#{i}] #{stats.n}"

  #       expect(stats.stdev).to be_within(precision).of(calc_stdev)
  #     end
  #   end
  # end

  describe ".synchonize" do
    it "preserves private methods" do
      expect(described_class.private_instance_methods).to include(:update)
    end

    it "makes Stats thread-safer" do
      fiber = Fiber.new do
        expect(stats.instance_variable_get(:@lock)).to be_locked
      end

      more_stats = described_class.new
      expect(more_stats).to receive(:n) { fiber.resume }

      stats << more_stats
    end
  end

  describe "#freeze" do
    before { stats.freeze }

    it { expect(stats.frozen?).to be true }

    it "prevents modification" do
      expect { stats << 1 }.to raise_error(FrozenError)
    end
  end
end
