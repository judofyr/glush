require_relative '../lib/glush'

module TestGrammars
  module_function

  def paren
    @paren ||= Glush::Grammar.new {
      rule \
      def paren
        eps | (str("(") >> paren >> str(")"))
      end

      paren
    }
  end

  def paren_one
    @paren_one ||= Glush::Grammar.new {
      rule \
      def paren
        str("1") >> str("2").maybe |
        str("(") >> paren >> str(")")
      end

      paren
    }
  end

  def right_recurse
    @right_recurse ||= Glush::Grammar.new {
      rule \
      def atom
        str("1")
      end

      rule \
      def s
        atom | (atom >> str("+") >> s)
      end

      s
    }
  end

  def empty_left_recursion
    @empty_left_recursion ||= Glush::Grammar.new {
      rule \
      def s
        s >> str("+") >> s |
        eps
      end

      s
    }
  end

  def super_ambigous
    # http://www.codecommit.com/blog/scala/unveiling-the-mysteries-of-gll-part-2
    @super_ambigous ||= Glush::Grammar.new {
      rule \
      def s
        s >> s >> s |
        s >> s |
        str("a")
      end

      s
    }
  end

  def three_a
    @three_a ||= Glush::Grammar.new {
      rule \
      def s
        s >> s >> s |
        str("a")
      end

      s
    }
  end

  def amb_expr
    @amb_expr ||= Glush::Grammar.new {
      rule \
      def expr
        expr >> str("+") >> expr |
        expr >> str("-") >> expr |
        expr >> str("*") >> expr |
        expr >> str("/") >> expr |
        str("1")
      end

      expr
    }
  end

  def manual_expr
    @manual_expr ||= Glush::Grammar.new {
      rule \
      def add_expr
        mark(:add) >> add_expr >> str("+") >> mul_expr |
        mark(:sub) >> add_expr >> str("-") >> mul_expr |
        mul_expr
      end

      rule \
      def mul_expr
        mark(:mul) >> mul_expr >> str("*") >> base |
        mark(:div) >> mul_expr >> str("/") >> base |
        base
      end

      def base
        mark(:one) >> str("1")
      end

      def expr
        add_expr
      end

      expr
    }
  end

  def utf8
    @utf8 ||= Glush::Grammar.new {
      rule \
      def main
        str("i") >> anyutf8 >> anyutf8 |
        str("a") >> anyascii |
        str("b") >> anytoken
      end

      main
    }
  end

  def comments
    @comments ||= Glush::Grammar.new {
      def comment
        str("#") >> utf8inv("\n").star >> str("\n")
      end

      rule \
      def main
        (str("a") >> comment.maybe).star
      end

      main
    }
  end
end

