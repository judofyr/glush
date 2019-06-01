module Glush
  class List
    def self.empty
      @empty ||= List.new
    end

    def self.[](item)
      new([item])
    end

    def initialize(data = [])
      @data = data
    end

    def add(other)
      List.new(@data + [other])
    end

    def each(&blk)
      @data.each(&blk)
    end
  end
end

