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

  describe "Enter set" do
    it "handles deeply nested calls" do
      s = Glush::DSL.build {
        def_rule :a do
          b | c
        end

        def_rule :b do
          d | str("d")
        end

        def_rule :d do
          str("e")
        end

        def_rule :c do
          str("f")
        end

        a
      }

      e = builder.enter_set(s)
      assert_equal 3, e.size
    end

    it "handles left recursive rules" do
      s = Glush::DSL.build {
        def_rule :a do
          a >> str("+") >> a |
          str("1")
        end

        a
      }

      e = builder.enter_set(s)
      assert_equal 1, e.size
    end
  end
end

class TestP1Parser < Minitest::Spec
  instance_eval &ParserSuite
  
  def create_parser(pattern)
    Glush::P1.new(pattern)
  end
end

  