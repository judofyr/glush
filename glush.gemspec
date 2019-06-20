# -*- encoding: utf-8 -*-
require 'date'

Gem::Specification.new do |s|
  s.name          = 'glush'
  s.version       = ENV['GEM_VERSION'] || "1.master"
  s.date          = Date.today.to_s

  s.authors       = ['Magnus Holm']
  s.email         = ['judofyr@gmail.com']
  s.summary       = 'Parser toolkit'

  s.require_paths = %w(lib)
  s.files         = Dir["lib/**/*.rb"]
  s.license       = '0BSD'
end

