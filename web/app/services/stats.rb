# Quartiles with linear interpolation, the same as Excel QUARTILE.INC (PRD → Business rules), so the
# box plot and its test fixture use one method
module Stats
  module_function

  def quartile(sorted, q)
    return nil if sorted.empty?
    position = (sorted.size - 1) * q
    lower = sorted[position.floor]
    upper = sorted[position.ceil]
    lower + (upper - lower) * (position - position.floor)
  end

  # [min, q1, median, q3, max] of the values within 1.5 × IQR, plus the outliers beyond
  def box(values)
    sorted = values.map(&:to_d).sort
    q1, median, q3 = quartile(sorted, 0.25), quartile(sorted, 0.5), quartile(sorted, 0.75)
    fence = (q3 - q1) * BigDecimal("1.5")
    inside = sorted.select { |v| v.between?(q1 - fence, q3 + fence) }
    { box: [ inside.first, q1, median, q3, inside.last ], outliers: sorted.reject { |v| v.between?(q1 - fence, q3 + fence) } }
  end
end
