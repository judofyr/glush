require 'set'

module Glush
  class GrammarError < StandardError
  end

  autoload :Grammar, __dir__ + '/glush/grammar.rb'
  autoload :Patterns, __dir__ + '/glush/patterns.rb'
  autoload :Parser, __dir__ + '/glush/parser.rb'
  autoload :List, __dir__ + '/glush/list.rb'
end

