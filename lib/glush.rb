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

  autoload :Grammar, __dir__ + '/glush/grammar.rb'
  autoload :Patterns, __dir__ + '/glush/patterns.rb'
  autoload :StateMachine, __dir__ + '/glush/state_machine.rb'

  autoload :SMParser, __dir__ + '/glush/sm_parser.rb'

  autoload :DefaultParser, __dir__ + '/glush/default_parser.rb'

  autoload :List, __dir__ + '/glush/list.rb'
  autoload :MarkProcessor, __dir__ + '/glush/mark_processor.rb'

  autoload :EBNF, __dir__ + '/glush/ebnf.rb'
end

