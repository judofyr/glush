require 'simplecov'
SimpleCov.start do
  add_filter "/test/"
end

require_relative '../lib/glush'
require_relative 'grammars'
require_relative 'parser_suite'

require 'minitest/autorun'

