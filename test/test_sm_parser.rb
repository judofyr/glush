require_relative 'helper'

class TestSMParser < Minitest::Spec
  instance_eval &ParserSuite
  
  def create_parser(grammar)
    Glush::SMParser.new(grammar)
  end
end

