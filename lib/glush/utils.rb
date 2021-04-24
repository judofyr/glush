require 'open3'

module Glush
  module Utils
    module_function

    def dump_dot(expr, filename)
      Open3.popen2("dot", "-Tpng", "-o", filename) do |stdin, stdout|
        stdout.close
        sb = Glush::P2::StateBuilder.new(expr)
        sb.dump_dot(stdin)
        stdin.close
      end
    end

    def inspect_char(code)
      chr = code.chr
      return '" "' if chr == " "
      chr.inspect[1...-1]
    end
  end
end
