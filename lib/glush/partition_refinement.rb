module Glush
  class PartitionRefinement
    class Partition
      attr_reader :elements

      def initialize(elements)
        @elements = elements
      end
    end

    def initialize(*args)
      @default_set = s = Partition.new(Set.new(*args))
      @partitions = [@default_set]
      @partition = {}
      s.elements.each do |value|
        @partition[value] = s
      end
    end

    def [](value)
      @partition.fetch(value)
    end

    def partitions
      @partitions
    end

    def partition_elements
      @partitions.map(&:elements)
    end

    def observe(set)
      hit = Hash.new { |h, k| h[k] = Set.new }
      set.each do |value|
        if @partition.has_key?(value)
          partition = @partition[value]
        else
          partition = @default_set
          @default_set.elements << value
          @partition[value] = partition
        end

        hit[partition] << value
      end

      hit.each do |partition, values|
        next if partition.elements == values
        new_partition = Partition.new(values)
        @partitions << new_partition
        values.each do |value|
          @partition[value] = new_partition
          partition.elements.delete(value)
        end
      end

      self
    end
  end
end
