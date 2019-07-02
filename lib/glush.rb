require 'set'

module Glush
  class GrammarError < StandardError
  end

  autoload :Grammar, __dir__ + '/glush/grammar.rb'
  autoload :Patterns, __dir__ + '/glush/patterns.rb'
  autoload :StateMachine, __dir__ + '/glush/state_machine.rb'

  autoload :SMParser, __dir__ + '/glush/sm_parser.rb'

  autoload :DirectParser, __dir__ + '/glush/direct_parser.rb'
  autoload :Parser, __dir__ + '/glush/parser.rb'
  autoload :List, __dir__ + '/glush/list.rb'
  autoload :MarkProcessor, __dir__ + '/glush/mark_processor.rb'

  autoload :EBNF, __dir__ + '/glush/ebnf.rb'
end

