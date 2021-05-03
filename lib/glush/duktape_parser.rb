require 'duktape'

module Glush
  class DuktapeParser
    def initialize(expr)
      @expr = expr
    end

    def generate_javascript
      result = String.new
      gen = JavaScriptGenerator.new(@expr)
      gen.write(result)
      result
    end

    def context
      @context ||= Duktape::Context.new.tap do |ctx|
        ctx.exec_string(generate_javascript, "input.js")
      end
    end

    def recognize?(str)
      context.call_prop("recognize", str)
    end

    def parse(str)
      result = context.call_prop("parse", str)
      if result["type"] == "success"
        ParseSuccess.new(result["marks"].map { |mark| Mark.new(mark["name"].to_sym, mark["position"].to_i) })
      else
        ParseError.new(result["position"].to_i)
      end
    end

    def parse!(str)
      parse(str).unwrap
    end
  end
end
