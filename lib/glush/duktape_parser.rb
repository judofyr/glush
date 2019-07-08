require 'duktape'

module Glush
  class DuktapeParser
    def initialize(grammar)
      js = JavaScriptGenerator.generate(grammar)
      @context = Duktape::Context.new
      @context.define_function("log") { |x| p x }
      @context.exec_string(js, "glush.generated.js")
    end

    def recognize?(input)
      @context.call_prop('recognize', input)
    end

    class Result
      def initialize(plain_marks)
        @plain_marks = plain_marks
      end

      def marks
        @marks ||= @plain_marks.map { |m|
          Mark.new(m["name"].to_sym, m["position"].to_i)
        }
      end
    end

    def parse(input)
      result = @context.call_prop('parse', input)
      case result["type"]
      when "error"
        position = result["position"].to_i
        ParseError.new(position)
      when "success"
        ParseSuccess.new(Result.new(result["marks"]))
      else
        raise "unknown type: #{result["type"].inspect}"
      end
    end
  end
end

