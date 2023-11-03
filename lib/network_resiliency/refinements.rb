module NetworkResiliency
  module Refinements
    refine Numeric do
      def order_of_magnitude(ceil: false)
        return 0 if self <= 0
        return 1 if self <= 1

        log10 = Math.log10(self.round)
        10 ** (ceil ? log10.ceil : log10.floor)
      end
    end
  end
end
