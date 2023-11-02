describe NetworkResiliency::Refinements do
  using NetworkResiliency::Refinements

  describe Numeric do
    describe "#order_of_magnitude" do
      it { expect(0.order_of_magnitude).to eq 0 }

      it { expect(0.1.order_of_magnitude).to eq 0.1 }
      it { expect(0.09.order_of_magnitude).to eq 0.1 }

      it { expect(0.9.order_of_magnitude).to eq 1 }
      it { expect(1.order_of_magnitude).to eq 1 }

      it { expect(2.order_of_magnitude).to eq 10 }
      it { expect(2.5.order_of_magnitude).to eq 10 }
      it { expect(10.order_of_magnitude).to eq 10 }

      it { expect(10.5.order_of_magnitude).to eq 100 }
      it { expect(20.order_of_magnitude).to eq 100 }
      it { expect(99.9.order_of_magnitude).to eq 100 }

      context "when negative" do
        it "raises an error" do
          expect { -1.order_of_magnitude }.to raise_error(Math::DomainError)
        end
      end
    end
  end
end
