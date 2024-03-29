describe NetworkResiliency::Refinements do
  using NetworkResiliency::Refinements

  describe Numeric do
    describe "#order_of_magnitude" do
      it { expect(0.order_of_magnitude).to eq 0 }

      it { expect(0.1.order_of_magnitude).to eq 1 }
      it { expect(0.9.order_of_magnitude).to eq 1 }
      it { expect(1.order_of_magnitude).to eq 1 }
      it { expect(2.order_of_magnitude).to eq 1 }
      it { expect(2.5.order_of_magnitude).to eq 1 }
      it { expect(9.order_of_magnitude).to eq 1 }

      it { expect(9.5.order_of_magnitude).to eq 10 }
      it { expect(10.order_of_magnitude).to eq 10 }
      it { expect(10.5.order_of_magnitude).to eq 10 }
      it { expect(90.order_of_magnitude).to eq 10 }
      it { expect(99.order_of_magnitude).to eq 10 }

      it { expect(99.9.order_of_magnitude).to eq 100 }
      it { expect(100.order_of_magnitude).to eq 100 }

      context "with ceil: true" do
        it { expect(0.order_of_magnitude(ceil: true)).to eq 0 }

        it { expect(0.1.order_of_magnitude(ceil: true)).to eq 1 }
        it { expect(0.09.order_of_magnitude(ceil: true)).to eq 1 }
        it { expect(0.9.order_of_magnitude(ceil: true)).to eq 1 }
        it { expect(1.order_of_magnitude(ceil: true)).to eq 1 }

        it { expect(2.order_of_magnitude(ceil: true)).to eq 10 }
        it { expect(2.5.order_of_magnitude(ceil: true)).to eq 10 }
        it { expect(10.order_of_magnitude(ceil: true)).to eq 10 }

        it { expect(10.5.order_of_magnitude(ceil: true)).to eq 100 }
        it { expect(20.order_of_magnitude(ceil: true)).to eq 100 }
        it { expect(99.9.order_of_magnitude(ceil: true)).to eq 100 }
      end

      context "when negative" do
        it { expect(-1.order_of_magnitude).to eq 0 }
        it { expect(-10.order_of_magnitude).to eq 0 }
      end
    end
  end

  describe "#power_ceil" do
    it { expect(0.power_ceil).to eq 0 }
    it { expect(1.power_ceil).to eq 1 }

    it { expect(0.1.power_ceil).to eq 1 }

    it { expect(10.power_ceil).to eq 10 }

    it { expect(11.power_ceil).to eq 20 }
    it { expect(13.power_ceil).to eq 20 }
    it { expect(19.power_ceil).to eq 20 }

    it { expect(111.power_ceil).to eq 200 }
    it { expect(234.power_ceil).to eq 300 }
  end
end
