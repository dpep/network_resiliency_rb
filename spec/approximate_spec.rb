describe "approximate" do
  let(:stats) { NetworkResiliency::Stats.new << 3 }

  it "matches approximates oneself" do
    expect(stats).to approximate stats
  end

  it "matches approximate avg" do
    other = NetworkResiliency::Stats.new
    allow(other).to receive(:n).and_return(stats.n)
    allow(other).to receive(:avg).and_return(stats.avg + 0.01)

    expect(other).to approximate stats
  end

  it "matches approximate stdev" do
    other = stats.dup
    allow(stats).to receive(:stdev).and_return(10)
    allow(other).to receive(:stdev).and_return(10.1)

    expect(other).to approximate stats
  end

  it "works without data" do
    stats = NetworkResiliency::Stats.new
    expect(stats).to approximate stats
  end

  it "catches erroneous input" do
    expect {
      expect(stats).to approximate 3
    }.to raise_error(ArgumentError)
  end
end
