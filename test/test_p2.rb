require_relative 'helper'

class TestP2Builder < Minitest::Spec
  let(:builder) do
    Glush::P2::Builder.new
  end

  describe "first_set" do
    it "retrieves marks" do
      s = Glush::DSL.build {
        mark(:a) >> str("a")
      }

      fst = builder.first_set(s)
      assert_equal 1, fst.size
      m, = *fst
      assert_equal [:a], m.marks
    end

    it "handles multiple marks" do
      s = Glush::DSL.build {
        mark(:a) >> mark(:b) >> str("a")
      }

      fst = builder.first_set(s)
      assert_equal 1, fst.size
      m, = *fst
      assert_equal [:a, :b], m.marks
    end
  end

  describe "direct_call_set" do
    it "includes itself" do
      s = Glush::DSL.build {
        def_rule :a do
          str("a")
        end

        a
      }

      c = builder.direct_call_set(s.rule)
      assert_equal 1, c.size
      a, = *c
      assert_equal "a", a.rule.name
      assert_equal Set[[]], a.before_marks
      assert_equal Set[[]], a.after_marks
    end

    it "is recursive" do
      s = Glush::DSL.build {
        def_rule :a do
          b
        end

        def_rule :b do
          c
        end

        def_rule :c do
          str("c")
        end

        a
      }

      c = builder.direct_call_set(s.rule)
      assert_equal 3, c.size
    end

    it "includes alises with marks" do
      s = Glush::DSL.build {
        def_rule :a do
          mark(:b) >> b >> mark(:after_b) |
          mark(:c) >> c >> str("c") |
          str("a")
        end

        def_rule :b do
          str("b")
        end

        def_rule :c do
          str("c")
        end

        a
      }

      set = builder.direct_call_set(s.rule)
      assert_equal 2, set.size

      a, b = *set.sort_by { |x| x.rule.name }
      assert_equal "a", a.rule.name
      assert_equal Set[[]], a.before_marks
      assert_equal Set[[]], a.after_marks

      assert_equal "b", b.rule.name
      assert_equal Set[[:b]], b.before_marks
      assert_equal Set[[:after_b]], b.after_marks
    end
  end

  describe "start_call_set" do
    it "returns all start calls" do
      s = Glush::DSL.build {
        def_rule :a do
          mark(:a) >> b >> str("a")
        end

        def_rule :b do
          mark(:b) >> c >> str("b")
        end
        
        def_rule :c do
          mark(:c) >> str("c")
        end

        a
      }

      set = builder.start_call_set(s.rule)
      assert_equal 2, set.size

      b, c = *set.sort_by { |s| s.invoke_rule.name }
      assert_equal "b", b.invoke_rule.name
      assert_equal "a", b.cont_rule.name
      assert_equal "b", b.cont_expr.rule.name
      assert_equal Set[[:a]], b.before_marks

      assert_equal "c", c.invoke_rule.name
      assert_equal "b", c.cont_rule.name
      assert_equal "c", c.cont_expr.rule.name
      assert_equal Set[[:b]], c.before_marks
    end

    it "follows direct calls" do
      s = Glush::DSL.build {
        def_rule :a do
          mark(:a) >> b >> str("a")
        end

        def_rule :b do
          mark(:b) >> c >> mark(:end_b)
        end

        def_rule :c do
          mark(:c) >> str("c")
        end

        a
      }

      set = builder.start_call_set(s.rule)

      assert_equal 3, set.size
      b, c1, c2 = *set.sort_by { |s| [s.invoke_rule.name, s.cont_rule.name] }

      assert_equal "b", b.invoke_rule.name
      assert_equal "a", b.cont_rule.name
      assert_equal "b", b.cont_expr.rule.name
      assert_equal Set[[:a]], b.before_marks
      assert_equal Set[[]], b.after_marks

      assert_equal "c", c1.invoke_rule.name
      assert_equal "a", c1.cont_rule.name
      assert_equal "b", c1.cont_expr.rule.name
      assert_equal Set[[:a, :b]], c1.before_marks
      assert_equal Set[[:end_b]], c1.after_marks

      assert_equal "c", c2.invoke_rule.name
      assert_equal "b", c2.cont_rule.name
      assert_equal "c", c2.cont_expr.rule.name
      assert_equal Set[[]], c2.after_marks
    end
  end
end

class TestP2Parser < Minitest::Spec
  instance_eval &ParserSuite
  
  def create_parser(pattern)
    Glush::P2.new(pattern)
  end
end

  