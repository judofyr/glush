require 'set'

module Glush
  class GrammarError < StandardError
  end

  Mark = Struct.new(:name, :position)

  class ParseError < StandardError
    attr_reader :position

    def initialize(position)
      @position = position
    end

    def error?
      true
    end

    def unwrap
      raise self
    end
  end

  class ParseSuccess
    def initialize(result)
      @result = result
    end

    def marks
      @result.marks
    end

    def error?
      false
    end

    def unwrap
      self
    end
  end

  autoload :DefaultParser, __dir__ + '/glush/default_parser.rb'
  autoload :DSL, __dir__ + '/glush/dsl.rb'
  autoload :Expr, __dir__ + '/glush/expr.rb'
  autoload :ExprMatcher, __dir__ + '/glush/expr_matcher.rb'
  autoload :FixpointBuilder, __dir__ + '/glush/fixpoint_builder.rb'
  autoload :List, __dir__ + '/glush/list.rb'
  autoload :MarkProcessor, __dir__ + '/glush/mark_processor.rb'
  autoload :P1, __dir__ + '/glush/p1.rb'
end

