module Glush
  module Patterns
    class Base
      attr_accessor :is_empty

      def consume!
        return copy.consume! if @consumed
        @consumed = true
        self
      end

      def empty?
        if defined?(@is_empty)
          @is_empty
        else
          raise "empty is not computed for #{self.class}"
        end
      end

      def >>(other)
        Seq.new(self, other)
      end

      def |(other)
        Alt.new(self, other)
      end

      def plus
        Plus.new(self)
      end

      def star
        plus.maybe
      end

      def maybe
        (self | Eps.new)
      end
    end

    module Terminal
      def self_set
        @self_set ||= Set[self]
      end

      def first_set
        self_set
      end

      def last_set
        self_set
      end

      def each_pair
      end
    end

    class Char < Base
      attr_reader :char

      def initialize(char)
        @char = char
      end

      def match?(char)
        @char == char
      end

      def copy
        Char.new(@char)
      end

      def calculate_empty(b)
        @is_empty = false
      end

      include Terminal

      def inspect
        "[#{@char}]"
      end
    end

    class Eps < Base
      def consume!
        self
      end

      def calculate_empty(b)
        @is_empty = true
      end

      EMPTY_SET = Set[]

      def first_set
        EMPTY_SET
      end

      def last_set
        EMPTY_SET
      end

      def each_pair
      end
    end

    class Alt < Base
      def initialize(left, right)
        @left = left.consume!
        @right = right.consume!
      end

      def copy
        Alt.new(@left, @right)
      end

      def calculate_empty(b)
        @is_empty = @left.calculate_empty(b) | @right.calculate_empty(b)
      end

      def first_set
        @first_set ||= @left.first_set | @right.first_set
      end

      def last_set
        @last_set ||= @left.last_set | @right.last_set
      end

      def each_pair(&blk)
        @left.each_pair(&blk)
        @right.each_pair(&blk)
      end
    end

    class Seq < Base
      def initialize(left, right)
        @left = left.consume!
        @right = right.consume!
      end

      def copy
        Seq.new(@left, @right)
      end

      def calculate_empty(b)
        @is_empty = @left.calculate_empty(b) & @right.calculate_empty(b)
      end

      def first_set
        @first_set ||= @left.empty? ? (@left.first_set | @right.first_set) : @left.first_set
      end

      def last_set
        @last_set ||= @right.empty? ? (@left.last_set | @right.last_set) : @right.last_set
      end

      def each_pair(&blk)
        @left.each_pair(&blk)
        @right.each_pair(&blk)

        @left.last_set.each do |a|
          @right.first_set.each do |b|
            yield a, b
          end
        end
      end
    end

    class Plus < Base
      def initialize(child)
        @child = child.consume!
      end

      def copy
        Plus.new(@child)
      end

      def calculate_empty(b)
        @is_empty = @child.calculate_empty(b)
      end

      def first_set
        @child.first_set
      end

      def last_set
        @child.last_set
      end

      def each_pair(&blk)
        @child.each_pair(&blk)
        @child.last_set.each do |a|
          @child.first_set.each do |b|
            yield a, b
          end
        end
      end
    end

    class Rule
      attr_reader :name, :calls

      def initialize(name, &blk)
        @name = name
        @code = blk
        @calls = []
      end

      def call
        name = "#{@name}_#{@calls.size}"
        call = RuleCall.new(name, self)
        @calls << call
        call
      end

      def body
        @body ||= @code.call.consume!
      end

      def inspect
        "<#{@name}>"
      end
    end

    class RuleCall < Base
      attr_reader :name, :rule

      def initialize(name, rule)
        @name = name
        @rule = rule
      end

      def copy
        RuleCall.new(@name, @rule)
      end

      def calculate_empty(b)
        @is_empty = b.include?(@rule)
      end

      include Terminal

      def inspect
        "<#{@name}>"
      end
    end
  end
end

