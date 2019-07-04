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
  end
end

