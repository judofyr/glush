require_relative '../lib/glush'

module TestGrammars
  module_function

  def paren
    @paren ||= Glush::DSL.build {
      def_rule :paren do
        eps | (str("(") >> paren >> str(")"))
      end

      paren
    }
  end

  def paren_one
    @paren_one ||= Glush::DSL.build {
      def_rule :paren do
        str("1") >> str("2").maybe |
        str("(") >> paren >> str(")")
      end

      paren
    }
  end

  def ones
    @ones ||= Glush::DSL.build {
      def_rule :s do
        s >> str("1") |
        str("1")
      end

      s
    }
  end

  def right_recurse
    @right_recurse ||= Glush::DSL.build {
      def_rule :atom do
        str("1")
      end

      def_rule :s do
        atom | (atom >> str("+") >> s)
      end

      s
    }
  end

  def empty_left_recursion
    @empty_left_recursion ||= Glush::DSL.build {
      def_rule :s do
        s >> str("+") >> s |
        eps
      end

      s
    }
  end

  def super_ambigous
    # http://www.codecommit.com/blog/scala/unveiling-the-mysteries-of-gll-part-2
    @super_ambigous ||= Glush::DSL.build {
      def_rule :s do
        s >> s >> s |
        s >> s |
        (str("a") | str("b"))
      end

      s
    }
  end

  def three_a
    @three_a ||= Glush::DSL.build {
      def_rule :s do
        s >> s >> s |
        str("a")
      end

      s
    }
  end

  def amb_expr
    @amb_expr ||= Glush::DSL.build {
      def_rule :expr do
        expr >> str("+") >> expr |
        expr >> str("-") >> expr |
        expr >> str("*") >> expr |
        expr >> str("/") >> expr |
        str("n")
      end

      expr
    }
  end

  def manual_expr
    @manual_expr ||= Glush::DSL.build {
      def_rule :add_expr do
        mark(:add) { add_expr >> str("+") >> mul_expr } |
        mark(:sub) { add_expr >> str("-") >> mul_expr } |
        mul_expr
      end

      def_rule :mul_expr do
        mark(:mul) { mul_expr >> str("*") >> base } |
        mark(:div) { mul_expr >> str("/") >> base } |
        base
      end

      def_rule :base, mark: :n do
        str("n")
      end

      def expr
       add_expr
      end

      expr
    }
  end

  def prec_expr
    @prec_expr ||= Glush::DSL.build {
      prec_rule :expr do |prec|
        prec.add(9) { mark(:n) { str("n") } }
        prec.add(1) { mark(:add) { expr(1) >> str("+") >> expr(2) } }
        prec.add(1) { mark(:sub) { expr(1) >> str("-") >> expr(2) } }
        prec.add(2) { mark(:mul) { expr(2) >> str("*") >> expr(3) } }
        prec.add(2) { mark(:div) { expr(2) >> str("/") >> expr(3) } }
        prec.add(3) { mark(:pow) { expr(4) >> str("^") >> expr(3) } }
      end

      expr
    }
  end

  def comments
    @comments ||= Glush::DSL.build {
      def comment
        str("#") >> inv(str("\n")).star >> str("\n")
      end

      def_rule :main do
        (str("a") >> comment.maybe).star
      end

      main
    }
  end
end

