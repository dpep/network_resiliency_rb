describe ApiAvenger::Stats do
  let(:precision) { 0.0001 }
  let(:stats) { described_class.new }

  def calc_avg(values)
    values.sum(0.0) / values.count
  end

  def calc_stdev(values)
    avg = calc_avg(values)
    sq_diff = values.sum(0.0) {|x| (x - avg) ** 2 }
    Math.sqrt(sq_diff / values.count)
  end

  describe 'helper methods' do
    specify 'sanity check' do
      data = [ 1, 2, 3, 4, 5 ]

      expect(calc_avg(data)).to eq 3
      expect(calc_stdev(data)).to eq(Math.sqrt(2))
    end

    specify 'another sanity check' do
      data = 1..31

      expect(calc_avg(data)).to eq 16
      expect(calc_stdev(data)).to be_within(precision).of(8.94427)
    end
  end

  describe '#<<' do
    it 'calculates the running average and stdev' do
      data = []

      1000.times do
        val = rand * 100

        data << val
        stats << val

        expect(stats.n).to eq data.count
        expect(stats.avg).to be_within(precision).of(calc_avg(data))
        expect(stats.stdev).to be_within(precision).of(calc_stdev(data))
      end
    end

    it 'accepts an array of values' do
      data = []

      10.times do
        values = rand(100).times.map { rand * 100 }

        data += values
        stats << values

        expect(stats.n).to eq data.count
        expect(stats.avg).to be_within(precision).of(calc_avg(data))
        expect(stats.stdev).to be_within(precision).of(calc_stdev(data))
      end
    end

    it 'accepts another ApiAvenger::Stats object' do
      data = []

      100.times do
        values = rand(100).times.map { rand * 100 }

        data += values
        stats << described_class.new(values)

        expect(stats.n).to eq data.count
        expect(stats.avg).to be_within(precision).of(calc_avg(data))

        expect(stats.stdev).to be_within(2).percent_of(calc_stdev(data))
        # expect(stats.stdev).to be_within(precision).of(calc_stdev(data))
      end
    end

    it 'works with small fractions' do
      data = 1000.times.map { rand }
      data.each {|x| stats << x }

      expect(stats.avg).to be_within(precision).of(calc_avg(data))
      expect(stats.stdev).to be_within(precision).of(calc_stdev(data))
    end
  end
end
