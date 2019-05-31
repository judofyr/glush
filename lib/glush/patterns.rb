module Glush
  module Patterns
    class Base
      attr_accessor :is_empty

      def consume!
        return copy.consume! if defined?(@consumed)
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

      def static?
        empty?
      end
    end

    class Token < Base
      attr_reader :token

      def initialize(token)
        @token = token
      end

      def match?(token)
        @token == token
      end

      def copy
        Token.new(@token)
      end

      def calculate_empty(b)
        @is_empty = false
      end

      include Terminal

      def inspect
        "[#{@token}]"
      end
    end

    module FixedToken
      def copy
        self.class.new
      end

      def calculate_empty(b)
        @is_empty = false
      end

      include Terminal

      def inspect
        self.class.name
      end
    end

    class Any < Base
      include FixedToken

      def match?(token)
        true
      end
    end

    class UTF8Char1 < Base
      include FixedToken
      RANGE = (0..0b0111_1111)

      def match?(token)
        RANGE.cover?(token)
      end

      def complete
        self
      end
    end

    class UTF8Char2 < Base
      include FixedToken
      RANGE = (0b1100_0000..0b1101_1111)

      def match?(token)
        RANGE.cover?(token)
      end

      def complete
        self >> UTF8CharLast.new
      end
    end

    class UTF8Char3 < Base
      include FixedToken
      RANGE = (0b1110_0000..0b1110_1111)

      def match?(token)
        RANGE.cover?(token)
      end

      def complete
        self >> UTF8CharLast.new >> UTF8CharLast.new
      end
    end

    class UTF8Char4 < Base
      include FixedToken
      RANGE = (0b1111_0000..0b1111_0111)

      def match?(token)
        RANGE.cover?(token)
      end

      def complete
        self >> UTF8CharLast.new >> UTF8CharLast.new >> UTF8CharLast.new
      end
    end

    class UTF8CharLast < Base
      include FixedToken
      RANGE = (0b1000_0000..0b1011_1111)

      def match?(token)
        RANGE.cover?(token)
      end
    end

    class Marker < Base
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def match?(token)
        true
      end

      def copy
        Marker.new(@name)
      end

      def calculate_empty(b)
        @is_empty = false
      end

      def static?
        true
      end

      include Terminal

      def inspect
        "mark(#{@name})"
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

    class NegativeToken < Base
      attr_reader :name

      def initialize(tokens)
        if !tokens.is_a?(Array)
          raise TypeError, "expected Array, got #{tokens.class}"
        end

        @tokens = tokens
      end

      def copy
        NegativeToken.new(@tokens)
      end

      def calculate_empty(b)
        @is_empty = false
      end

      def match?(token)
        !@tokens.include?(token)
      end

      def static?
        true
      end

      include Terminal

      def inspect
        "neg(#{@tokens.map(&:inspect).join(", ")})"
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

      def static?
        @left.static? or @right.static?
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

      def static?
        @left.static? && @right.static?
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

      def static?
        @child.static?
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

