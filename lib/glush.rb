require 'set'

module Glush
  class GrammarError < StandardError
  end

  Mark = Struct.new(:name, :position)

  class ParseError < StandardError
    attr_reader :position

    def initialize(position)
      @position = position
      super("parse error at #{position}")
    end

    def error?
      true
    end

    def unwrap
      raise self
    end
  end

  class ParseSuccess
    attr_reader :data

    def initialize(data)
      @data = data
    end

    def error?
      false
    end

    def unwrap
      self
    end
  end

  autoload :CLI, __dir__ + '/glush/cli.rb'
  autoload :DefaultParser, __dir__ + '/glush/default_parser.rb'
  autoload :DSL, __dir__ + '/glush/dsl.rb'
  autoload :EBNF, __dir__ + '/glush/ebnf.rb'
  autoload :Expr, __dir__ + '/glush/expr.rb'
  autoload :ExprMatcher, __dir__ + '/glush/expr_matcher.rb'
  autoload :FixpointBuilder, __dir__ + '/glush/fixpoint_builder.rb'
  autoload :MarkProcessor, __dir__ + '/glush/mark_processor.rb'
  autoload :PartitionRefinement, __dir__ + '/glush/partition_refinement.rb'
  autoload :P1, __dir__ + '/glush/p1.rb'
  autoload :P2, __dir__ + '/glush/p2.rb'
  autoload :Utils, __dir__ + '/glush/utils.rb'
end

