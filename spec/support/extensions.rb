# frozen_string_literal: true

class Object
  def equivalent_jsonld?(other, ordered: false)
    self == other
  end
end

class Hash
  def equivalent_jsonld?(other, ordered: false)
    return false unless other.is_a?(Hash) && other.length == length

    all? do |key, value|
      # List values are still ordered
      if key == '@language' && value.is_a?(String)
        value.downcase.equivalent_jsonld?(other[key].to_s.downcase, ordered: key == '@list')
      else
        value.equivalent_jsonld?(other[key], ordered: key == '@list')
      end
    end
  end

  def diff(other)
    keys.each_with_object({}) do |key, memo|
      memo[key] = [self[key], other[key]] unless self[key] == other[key]
    end
  end
end

class Array
  def equivalent_jsonld?(other, ordered: false)
    return false unless other.is_a?(Array) && other.length == length

    if ordered
      b = other.dup
      # All elements must match in order
      all? { |av| av.equivalent_jsonld?(b.shift) }
    else
      # Look for any element which matches
      all? do |av|
        other.any? { |bv| av.equivalent_jsonld?(bv) }
      end
    end
  end
end
