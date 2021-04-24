require_relative 'helper'

class TestP1 < Minitest::Spec
  let(:builder) do
    Glush::P1::Builder.new
  end

  describe "Nullable" do
    it "handles calls" do
      s = Glush::DSL.build {
        def_rule :a do
          str("a").maybe | str("c")
        end

        a
      }

      assert builder.nullable(s)
    end

    it "supports recursive rules" do
      s = Glush::DSL.build {
        def_rule :a do
          a >> str("a").maybe | str("c")
        end

        a
      }

      refute builder.nullable(s)
    end
  end

  describe :call_set do
    it "handles tail recursive with aliases" do
      b = nil
      c = nil

      s = Glush::DSL.build {
        def_rule :a do
          b >> str("a")
        end

        def_rule :b do
          c >> str("b")
        end

        def_rule :c do
          str("c")
        end

        b = self.b
        c = self.c

        a
      }

      call_set = builder.call_set(s)
      assert_includes call_set, [nil, s, s.rule]
      assert_includes call_set, [s.rule, b, b.rule]
      assert_includes call_set, [b.rule, c, c.rule]
    end
  end
end

class TestP1Parser < Minitest::Spec
  instance_eval(&ParserSuite)
  
  def create_parser(pattern)
    Glush::P1.new(pattern)
  end
end

  