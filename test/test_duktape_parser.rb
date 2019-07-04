require_relative 'helper'

class TestDuktapeParser < Minitest::Spec
  instance_eval &ParserSuite

  def create_parser(grammar)
    Glush::DuktapeParser.new(grammar)
  end
end


