module Glush
  # This is the new interface that I want to support in all parsers
  class DirectParser
    def initialize(grammar)
      @grammar = grammar
    end

    def recognize?(input)
      Parser.recognize_string?(@grammar, input)
    end

    def parse(input)
      Parser.parse_string(@grammar, input)
    end

    def parse!(input)
      result = parse(input)
      if !result.valid?
        raise "parser failed"
      end
      result
    end
  end
end

