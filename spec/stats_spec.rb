describe ApiAvenger::Stats do
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
    it 'starts at 0' do
      expect(stats.n).to be 0
    end

    it 'accumulates correctly' do
      1_000.times do |i|
        stats << 0

        expect(stats.n).to be (i + 1)
      end

      expect(stats.n).to be 1_000
    end
  end

  describe '#avg' do
    it do
      1_000.times do |i|
        stats << 3

        expect(stats.avg).to eq 3
      end
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

    it 'works with LOTS of random numbers' do
      100_000.times.map { choose }.each_slice(10_000) do |nums|
        data << nums
        stats << nums

        check
      end

      expect(stats.n).to eq 100_000
    end
  end

  describe '#stdev' do
    it do
      1_000.times do |i|
        stats << 3

        expect(stats.stdev).to eq 0
      end
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

    it 'works with LOTS of random numbers' do
      100_000.times.map { choose }.each_slice(10_000) do |nums|
        data << nums
        stats << nums

        check
      end

      expect(stats.n).to eq 100_000
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

      more_stats = described_class.new
      more_stats << [ 3, 4, 5 ]
      stats << more_stats

      data << [ 1, 2, 3, 4, 5 ]

      check
    end

    it 'accepts many Stats objects' do
      other_stats = described_class.new

      expect(stats).to receive(:merge!).with(other_stats)
      stats << other_stats
    end
  end

  describe '#merge' do
    it do
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
  end

  describe "#variance" do
    before { stats << 1_000.times.map { choose } }

    it { expect(Math.sqrt(stats.variance)).to eq(stats.stdev) }

    describe "of a sample" do
      it { expect(stats.variance(sample: true)).to be > stats.variance }
    end
  end
end
