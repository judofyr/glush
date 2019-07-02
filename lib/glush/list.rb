module Glush
  module List
    def self.empty
      @empty ||= EmptyList.new
    end

    def self.branched(alternatives)
      if alternatives.size == 1
        alternatives[0]
      else
        BranchedList.new(alternatives)
      end
    end

    class Base
      def add(data)
        Push.new(self, data)
      end

      def add_list(list)
        Concat.new(self, list)
      end

      def to_a
        result = []
        each { |item| result << item }
        result
      end
    end

    class EmptyList < Base
      def each
      end
    end

    class BranchedList < Base
      def initialize(alternatives)
        @alternatives = alternatives
      end

      def each(&blk)
        if @alternatives.size != 1
          raise "ambiguous"
        end
        @alternatives[0].each(&blk)
      end
    end

    class Push < Base
      def initialize(parent, data)
        @parent = parent
        @data = data
      end

      def each(&blk)
        @parent.each(&blk)
        yield @data
      end
    end

    class Concat < Base
      def initialize(left, right)
        @left = left
        @right = right
      end

      def each(&blk)
        @left.each(&blk)
        @right.each(&blk)
      end
    end
  end
end

