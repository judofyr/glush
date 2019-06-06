require_relative 'helper'

class TestEBNF < Minitest::Spec
  def recognize?(grammar, input)
    Glush::Parser.recognize_string?(grammar, input)
  end

  def self.assert_valid
    it "should be valid" do
      assert recognize?(Glush::EBNF::Grammar, ebnf), "should be valid"
    end
  end

  def self.refute_valid
    it "should not be valid" do
      refute recognize?(Glush::EBNF::Grammar, ebnf), "should not valid"
    end
  end

  def self.assert_matches(input)
    it "should match" do
      grammar = Glush::EBNF.parse(ebnf)
      assert recognize?(grammar, input), "should match: #{input}"
    end
  end

  def self.refute_matches(input)
    it "should not match" do
      grammar = Glush::EBNF.parse(ebnf)
      refute recognize?(grammar, input), "should not match: #{input}"
    end
  end

  def self.assert_marks(input, marks)
    it "should match marks" do
      grammar = Glush::EBNF.parse(ebnf)
      result = Glush::Parser.parse_string(grammar, input)
      assert result.valid?, "expected match for input: #{input}"
      assert_equal result.marks.map(&:to_a), marks
    end
  end

  describe("simple ebnf") do
    let(:ebnf) { %{
      S = AB*
      AB = A B
      A = 'a'+
      B = 'b'+
    } }

    assert_valid

    assert_matches ""
    assert_matches "ab"
    assert_matches "aabb"
    assert_matches "aaaaabbaaabbb"
    refute_matches "aaabbbbaa"
  end

  describe("alt precedence") do
    let(:ebnf) { %{
      S = A B | C D
      A = 'a'
      B = 'b'
      C = 'c'
      D = 'd'
    } }

    assert_matches "ab"
    assert_matches "cd"
    refute_matches "ac"
  end

  describe("postfix multi precedence") do
    let(:ebnf) { %{
      S = 'a'+*
    } }

    refute_valid
  end

  describe("postfix precedence") do
    let(:ebnf) { %{
      S = (A B)? C D?
      A = 'a'
      B = 'b'
      C = 'c'
      D = 'd'
    } }

    assert_valid

    assert_matches "abcd"
    assert_matches "cd"
    assert_matches "c"
    refute_matches ""
  end

  describe("marks") do
    let(:ebnf) { %{
      S = (A | B)+
      A = $foo 'a'
      B = $bar 'b'
    } }

    assert_marks "aa", [[:foo, 0], [:foo, 1]]
    assert_marks "ab", [[:foo, 0], [:bar, 1]]
  end

  describe("presedence") do
    let(:ebnf) { %{
      M = ":" S

      S =
       1| $add S^1 "+" S^2
       1| $sub S^1 "-" S^2
       2| $mul S^2 "*" S^3
       2| $div S^2 "/" S^3
       9| n

      n = $n 'n'
    } }

    assert_marks ":n+n", [[:add, 1], [:n, 1], [:n, 3]]
    assert_marks ":n+n*n", [[:add, 1], [:n, 1], [:mul, 3], [:n, 3], [:n, 5]]
  end

  describe("extra |") do
    let(:ebnf) { %{
      S =
        | 'a'
        | 'b'
    } }

    assert_matches "a"
    assert_matches "b"
  end
end

