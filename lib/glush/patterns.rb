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

      def single_token?
        false
      end

      def >>(other)
        Seq.new(self, other)
      end

      def |(other)
        Alt.new(self, other)
      end

      def &(other)
        Conj.new(self, other)
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

    Less = Struct.new(:token) do
      def ===(value)
        value <= token
      end

      def inspect
        "less(#{token})"
      end
    end

    Greater = Struct.new(:token) do
      def ===(value)
        value >= token
      end

      def inspect
        "greater(#{token})"
      end
    end

    class Token < Base
      attr_reader :choice

      def initialize(choice)
        if ![Integer, Range, Less, Greater, NilClass].any? { |x| choice.is_a?(x) }
          raise TypeError, "unsupported choice: #{choice.class}"
        end

        @choice = choice
      end

      def single_token?
        true
      end

      def match?(token)
        if token.nil?
          false
        else
          if @choice.nil?
            # any
            true
          else
            @choice === token
          end
        end
      end

      def invert
        case @choice
        when Integer
          Token.new(Less.new(@choice - 1)) |
          Token.new(Greater.new(@choice + 1))
        when Range
          Token.new(Less.new(@choice.begin - 1)) |
          Token.new(Greater.new(@choice.end + 1))
        else
          raise "Unknown type: #{@choice}"
        end
      end

      def copy
        Token.new(@choice)
      end

      def calculate_empty(b)
        @is_empty = false
      end

      include Terminal

      def inspect
        "#{@choice.inspect}"
      end
    end

    class Marker < Base
      attr_reader :name

      def initialize(name)
        @name = name
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

      def static?
        false
      end

      def each_pair
      end

      def inspect
        "eps"
      end
    end

    class Alt < Base
      attr_reader :left, :right

      def initialize(left, right)
        @left = left.consume!
        @right = right.consume!
      end

      def copy
        Alt.new(@left, @right)
      end

      def single_token?
        @left.single_token? && @right.single_token?
      end

      def match?(token)
        @left.match?(token) || @right.match?(token)
      end

      def invert
        @left.invert & @right.invert
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

      def inspect
        "alt(#{@left.inspect}, #{@right.inspect})"
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

      def inspect
        "seq(#{@left.inspect}, #{@right.inspect})"
      end
    end

    class Conj < Base
      Finalizer = Struct.new(:id, :type)

      def initialize(left, right)
        @left = left.consume!
        @right = right.consume!
      end

      def single_token?
        @left.single_token? && @right.single_token?
      end

      def match?(token)
        @left.match?(token) && @right.match?(token)
      end

      def calculate_empty(b)
        @is_empty = @left.calculate_empty(b) & @right.calculate_empty(b)
      end

      def static?
        @left.static? && @right.static?
      end

      def first_set
        @first_set ||= @left.first_set | @right.first_set
      end

      def last_set
        @last_set ||= Set[self]
      end

      def each_pair(&blk)
        @left.each_pair(&blk)
        @right.each_pair(&blk)

        @left.last_set.each do |lst|
          yield lst, Finalizer.new(self, :left)
        end

        @right.last_set.each do |lst|
          yield lst, Finalizer.new(self, :right)
        end
      end

      def inspect
        "conj(#{@left.inspect}, #{@right.inspect})"
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

      def inspect
        "plus(#{@child.inspect})"
      end
    end

    class Rule
      attr_reader :name, :calls, :guard

      def initialize(name, &blk)
        @name = name
        @code = blk
        @calls = []
      end

      def guard=(pattern)
        if !pattern.single_token?
          raise TypeError, "only single token patterns can be used as guard"
        end

        @guard = pattern
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

