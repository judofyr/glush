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
end

