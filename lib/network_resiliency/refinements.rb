module NetworkResiliency
  module Refinements
    refine Numeric do
      def order_of_magnitude
        self == 0 ? 0 : 10 ** Math.log10(self).ceil
      end
    end
  end
end
