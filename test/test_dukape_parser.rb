require_relative 'helper'

class TestDuktapeParser < Minitest::Spec
  instance_eval(&ParserSuite)
  
  def create_parser(pattern)
    Glush::DuktapeParser.new(pattern)
  end
end

  