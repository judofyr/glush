require_relative 'helper'

class TestParser < Minitest::Spec
  def recognize?(grammar, input)
    Glush::Parser.recognize_string?(grammar, input)
  end

  def self.assert_recognize(input)
    it "should recognize" do
      assert recognize?(grammar, input), "expected match for input: #{input}"
    end
  end

  def self.refute_recognize(input)
    it "should not recognize" do
      refute recognize?(grammar, input), "expected no match for input: #{input}"
    end
  end

  def self.assert_marks(input, marks)
    it "should match marks" do
      parser = Glush::Parser.new(grammar)
      parser.push_string(input)
      parser.close
      assert parser.final?, "expected match for input: #{input}"
      assert_equal parser.flat_marks.map(&:to_a), marks
    end
  end

  describe(:paren) do
    let(:grammar) { TestGrammars.paren }

    assert_recognize ""
    refute_recognize "("
    assert_recognize "()"
    assert_recognize "(())"
  end

  describe(:empty_left_recursion) do
    let(:grammar) { TestGrammars.empty_left_recursion }

    assert_recognize ""
    assert_recognize "+"
    assert_recognize "++"
    refute_recognize "++-"
  end

  describe(:super_ambigous) do
    let(:grammar) { TestGrammars.super_ambigous }

    assert_recognize "a"
    assert_recognize "aa"
    assert_recognize "aaa"
    assert_recognize "aaaa"
    assert_recognize "aaaaa"
    assert_recognize "aaaaaa"
  end

  describe(:three_a) do
    let(:grammar) { TestGrammars.three_a }

    assert_recognize "a"
    refute_recognize "aa"
    assert_recognize "aaa"
    refute_recognize "aaaa"
    assert_recognize "aaaaa"
  end

  describe(:amb_expr) do
    let(:grammar) { TestGrammars.amb_expr }

    assert_recognize "n"
    assert_recognize "n+n"
    assert_recognize "n+n*n/n-n*n-n"
    refute_recognize "n+n*n/n-nn-n"
  end

  describe(:manual_expr) do
    let(:grammar) { TestGrammars.manual_expr }

    assert_recognize "n"
    assert_recognize "n+n"
    assert_recognize "n+n*n/n-n*n-n"
    refute_recognize "n+n*n/n-nn-n"

    assert_marks "n", [[:n, 0]]
    assert_marks "n+n", [[:add, 0], [:n, 0], [:n, 2]]
    assert_marks "n+n*n+n", [
      [:add, 0],
        [:add, 0],
          [:n, 0],
          [:mul, 2],
            [:n, 2],
            [:n, 4],
        [:n, 6]
    ]
  end

  it "should reject empty mark rules" do
    assert_raises Glush::GrammarError do
      g = Glush::Grammar.new {
        def_rule :m do
          mark(:empty) |
          mark(:non_empty) >> str("a")
        end

        def_rule :main do
          m | m >> str("a")
        end

        main
      }

      recognize?(g, "a")
    end
  end

  it "should reject seq empty mark rules" do
    assert_raises Glush::GrammarError do
      g = Glush::Grammar.new {
        def_rule :m do
          mark(:empty) >> mark(:empty)
        end

        def_rule :main do
          m | m >> str("a")
        end

        main
      }

      recognize?(g, "a")
    end
  end

  it "should reject many empty mark rules" do
    assert_raises Glush::GrammarError do
      g = Glush::Grammar.new {
        def_rule :m do
          mark(:empty).plus
        end

        def_rule :main do
          m | m >> str("a")
        end

        main
      }

      recognize?(g, "a")
    end
  end

  describe(:utf8) do
    let(:grammar) { TestGrammars.utf8 }

    # UTF-8
    assert_recognize "iaa"
    assert_recognize "iøa"
    assert_recognize "i🎉b"
    refute_recognize ["i", 0xFF].pack("aC*")
    refute_recognize ["i", 0xFF, 0xFF].pack("aC*")

    # ASCII
    assert_recognize "a@"
    refute_recognize "aø"

    # Bytes
    assert_recognize ["b", 0xFF].pack("aC*")
  end

  describe(:comments) do
    let(:grammar) { TestGrammars.comments }

    assert_recognize "aa"
    assert_recognize "a#\n"
    assert_recognize "a#anything!🎉\naa"
    assert_recognize "a#anything!🎉\na#more\n"
    refute_recognize "a#"
  end

  describe("re-used patterns") do
    let(:grammar) do
      Glush::Grammar.new {
        def_rule :main do
          foo = str("a")
          foo >> foo >> foo
        end

        main
      }
    end

    refute_recognize "a"
    refute_recognize "aa"
    assert_recognize "aaa"
    refute_recognize "aaaa"
  end

  describe("precedence") do
    let(:grammar) { TestGrammars.prec_expr }

    assert_recognize "n"
    assert_recognize "n+n"
    assert_recognize "n+n+n"
    assert_marks "n+n+n", [
      [:add, 0],
        [:add, 0],
          [:n, 0],
          [:n, 2],
        [:n, 4],
    ]

    assert_marks "n+n-n", [
      [:sub, 0],
        [:add, 0],
          [:n, 0],
          [:n, 2],
        [:n, 4],
    ]

    assert_marks "n^n^n", [
      [:pow, 0],
        [:n, 0],
        [:pow, 2],
          [:n, 2],
          [:n, 4],
    ]
  end

  describe("conj") {
    let(:grammar) {
      Glush::Grammar.new {
        def_rule :s do
          (str("a").plus >> b) &
          (a >> str("c").plus)
        end

        def_rule :a do
          str("a") >> a.maybe >> str("b")
        end

        def_rule :b do
          str("b") >> b.maybe >> str("c")
        end

        s
      }
    }

    assert_recognize "abc"
    assert_recognize "aabbcc"
    refute_recognize "aabbc"
  }
end

