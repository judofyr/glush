require_relative '../lib/glush'
require_relative 'grammars'

require 'benchmark'

class Perf
  Parser = Glush::DirectParser

  def self.run
    parser = Parser.new(grammar)

    range.each do |n|
      print n, " "
      str = build(n)
      time = Benchmark.measure do
        result = parser.recognize?(str)
        raise "failed to recognize" if !result
      end
      print time.real, "\n"
    end
  end
end

class APerf < Perf
  def self.range
    (30..80).step(5)
  end
  
  def self.build(n)
    "a" * n
  end

  def self.grammar
    TestGrammars.super_ambigous
  end
end

class Expr < Perf
  OPS = %w[+ - * /]

  def self.build(n)
    ops = OPS.cycle
    str = String.new
    n.times do
      str << "n#{ops.next}"
    end
    str << "n"
  end
end

class AmbExpr < Expr
  def self.range
    (30..150).step(5)
  end

  def self.grammar
    TestGrammars.amb_expr
  end
end

class ManExpr < Expr
  def self.range
    (3000..7000).step(100)
  end

  def self.grammar
    TestGrammars.manual_expr
  end
end

class PrecExpr < ManExpr
  def self.grammar
    TestGrammars.prec_expr
  end
end

runners = {
  "a" => APerf,
  "ambexpr" => AmbExpr,
  "manexpr" => ManExpr,
  "precexpr" => PrecExpr,
}

if runner = runners[ARGV[0]]
  runner.run
else
  puts "usage: #{$0} #{runners.keys.join("|")}"
end

