require 'open3'

module Glush
  module Utils
    module_function

    def build_dot(filename, &blk)
      format = filename[/\.([^\.]+)/, 1]
      Open3.popen2e("dot", "-T#{format}", "-o", filename) do |stdin, stdout, waiter|
        yield stdin
        stdin.close
        out = stdout.read
        raise "dot error: #{out}" if !waiter.value.success?
      end
    end

    def build_dot_expr(expr, filename)
      build_dot(filename) do |stdin|
        sb = Glush::P2::StateBuilder.new(expr)
        sb.dump_dot(stdin)
      end
    end

    def inspect_char(code)
      chr = code.chr
      return '" "' if chr == " "
      chr.inspect[1...-1]
    end
  end
end
