require 'cri'

module Glush
  class CLI
    def self.run(argv = ARGV)
      new.command.run(argv)
    end

    def load_grammar(filename)
      err "--grammar required" if filename.nil?
      ebnf = File.read(filename)
      EBNF.create_grammar(ebnf)
    end

    def err(msg)
      puts "Error: #{msg}"
      exit 1
    end

    def command
      @command ||= Cri::Command.define do |c|
        c.name "glush"
        c.summary "parser toolkit"

        c.option :g, :grammar, "grammar file", argument: :required
        c.flag :h, :help, 'show help for this command' do |value, cmd|
          puts cmd.help
          exit 0
        end

        c.run do |opts, args, cmd|
          puts cmd.help
          exit 0
        end

        c.subcommand do |c|
          c.name "parse"
          c.summary "parse a string"
          c.usage "parse -g <grammar-file> <text>"

          c.param :text

          c.run do |opts, args, cmd|
            expr = load_grammar(opts[:grammar])
            parser = DefaultParser.new(expr)
            result = parser.parse(args[:text])
            if result.error?
              puts "Error: Failed to parse text at position #{result.position}"
              exit 1
            end

            result.data.each do |mark|
              p [mark.position, mark.name]
            end
          end
        end

        c.subcommand do |c|
          c.name "gen-js"
          c.summary "generate JavaScript parser"
          c.usage "gen-js -g <grammar-file>"

          c.no_params

          c.run do |opts, args, cmd|
            expr = load_grammar(opts[:grammar])
            gen = JavaScriptGenerator.new(expr, export: :esm)
            gen.write($stdout)
          end
        end

        c.subcommand do |c|
          c.name "viz"
          c.summary "produce diagram for grammar"
          c.usage "viz -g <grammar-file> <output-file>"

          c.param :filename

          c.run do |opts, args, cmd|
            expr = load_grammar(opts[:grammar])
            filename = args[:filename]
            Utils.build_dot_expr(expr, filename)
            puts "#{filename} created."
          end
        end
      end
    end
  end
end