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

    assert_recognize "1"
    assert_recognize "1+1"
    assert_recognize "1+1*1/1-1*1-1"
    refute_recognize "1+1*1/1-11-1"
  end

  describe(:manual_expr) do
    let(:grammar) { TestGrammars.manual_expr }

    assert_recognize "1"
    assert_recognize "1+1"
    assert_recognize "1+1*1/1-1*1-1"
    refute_recognize "1+1*1/1-11-1"

    assert_marks "1", [[:one, 0]]
    assert_marks "1+1", [[:add, 0], [:one, 0], [:one, 2]]
    assert_marks "1+1*1+1", [
      [:add, 0],
        [:add, 0],
          [:one, 0],
          [:mul, 2],
            [:one, 2],
            [:one, 4],
        [:one, 6]
    ]
  end
end

