module Glush
  class DSL
    def self.build(&blk)
      new.instance_eval(&blk)
    end

    def anytoken
      Expr::Any.new
    end

    def token(choice)
      Expr::Equal.new(choice)
    end

    def str(text)
      case text
      when String
        text.codepoints
          .map { |c| token(c) }
          .reduce { |a, b| a >> b }
      when Range
        a = text.begin
        b = text.end

        if a.size != 1 || b.size != 1
          raise GrammarError, "only single-character supported in range"
        end

        a_num = a.ord
        b_num = b.ord

        if b_num < a_num
          raise GrammarError, "invalid range"
        end

        Expr::Greater.new(a_num - 1) & Expr::Less.new(b_num - 1)
      else
        raise GrammarError, "unsupported type: #{text.inspect}"
      end
    end

    def inv(expr)
      case expr
      when Expr::Equal
        Expr::Less.new(expr.token - 1) | Expr::Greater.new(expr.token + 1)
      else
        raise "cannot invert: #{expr.inspect}"
      end
    end

    def eps
      Expr::Eps.new
    end

    def mark(name = :mark)
      Expr::Marker.new(name)
    end

    def sep_by(p, sep)
      sep_by1(p, sep).maybe
    end

    def sep_by1(p, sep)
      p >> (sep >> p).star
    end

    def end_by(p, sep)
      end_by1(p, sep).maybe
    end

    def end_by1(p, sep)
      (p >> sep).plus
    end

    def def_rule(name, &blk)
      rule = _new_rule(name.to_s, &blk)
      define_singleton_method(name) { rule.call }
    end

    class PrecBuilder
      def initialize(grammar, name)
        @alternatives = Hash.new { |h, k| h[k] = [] }
        @rules = Hash.new do |h, level|
          h[level] = grammar._new_rule("#{name}^#{level}") { pattern_for(level) }
        end
      end

      def add(pattern_level, &blk)
        @alternatives[pattern_level] << blk
        self
      end

      def levels
        @levels ||= @alternatives.keys.sort
      end

      def pattern_for(level)
        pattern = @alternatives[level].map(&:call).reduce { |a, b| a | b }

        if next_level = levels.detect { |l| l > level }
          pattern |= call_for(next_level)
        end

        pattern
      end

      def resolve_level(level)
        level = 0 if level.nil?
        actual_level = levels.detect { |l| l >= level }
        if !actual_level
          raise GrammarError, "unknown precedence level: #{level}"
        end
        actual_level
      end

      def call_for(level)
        @rules[level].call
      end
    end

    def prec_rule(name, &blk)
      builder = PrecBuilder.new(self, name)
      yield builder

      define_singleton_method(name) do |level=nil|
        level = builder.resolve_level(level)
        builder.call_for(level)
      end
    end

    def _new_rule(name, &blk)
      Expr::Rule.new(name, &blk)
    end
  end
end