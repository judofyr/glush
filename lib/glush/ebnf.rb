module Glush
  class EBNF
    Grammar = ::Glush::Grammar.new {
      def_rule :ebnf_rule do
        mark(:rule) >> ident >> ign >> ebnf_rule_sep >> ign >> ebnf_pattern |
        mark(:prec_rule) >> ident >> ign >> ebnf_rule_sep >> ign >> ebnf_prec_branches
      end

      def ebnf_rule_sep
        str(":") | str(":=") | str("::=") | str("=")
      end

      def ebnf_rule_end
        str(";") | str(".")
      end

      def braced_pattern(l, r)
        str(l) >> ign >> ebnf_pattern >> ign >> str(r)
      end

      def postfix_pattern(r, level=0)
        ebnf_pattern(level) >> ign >> str(r)
      end

      prec_rule :ebnf_pattern do |p|
        p.add(1)  { mark(:alt) >> ebnf_pattern(1) >> ign >> str("|") >> ign >> ebnf_pattern(2) }
        p.add(2)  { mark(:seq) >> ebnf_pattern(2) >> ign >> (str(",") >> ign).maybe >> ebnf_pattern(3) }

        p.add(3)  { mark(:opt) >> postfix_pattern("?", 4) }
        p.add(3)  { mark(:plus) >> postfix_pattern("+", 4) }
        p.add(3)  { mark(:star) >> postfix_pattern("*", 4) }

        p.add(10) { mark(:group) >> braced_pattern("(", ")") }
        p.add(10) { mark(:opt)   >> braced_pattern("[", "]") }
        p.add(10) { mark(:star)  >> braced_pattern("{", "}") }

        p.add(10) { mark(:pident) >> ident }
        p.add(10) { mark(:pident_level) >> ident >> str("^") >> number }
        p.add(10) { mark(:pstring) >> ebnf_str }
        p.add(10) { mark(:pmark) >> str("$") >> ident }
      end

      def_rule :ebnf_prec_branches do
        sep_by1(
          mark(:prec_branch) >> number >> str("|") >> ign >> ebnf_pattern,
          ign
        )
      end

      ## Whitespace

      def ign
        whitespace | comment
      end

      def whitespace
        (str(" ") | str("\n")).star
      end

      def comment
        str("#") >> inv(str("\n")).star >> str("\n")
      end

      def ebnf_str
        str("\"") >> mark(:string) >> inv(str("\"")).star >> mark >> str("\"") |
        str("'")  >> mark(:string) >> inv(str("'")).star  >> mark >> str("'")
      end

      def ident_fst
        str("a".."z") | str("A".."Z")
      end

      def ident_rest
        ident_fst | str("0".."9")
      end

      def_rule :number do
        mark(:number) >> str("0".."9").plus >> mark
      end

      def_rule :ident, guard: inv(ident_rest) do
        mark(:ident) >> ident_fst >> ident_rest.star >> mark
      end

      def_rule :main do
        ign >> sep_by(ebnf_rule, ign) >> ign
      end

      main
    }

    class Processor
      attr_reader :grammar

      def initialize(marks, string)
        @marks = marks
        @string = string
        @index = 0
        @grammar = Glush::Grammar.new

        @calls = Hash.new
        @precs = Hash.new
      end

      def compile_pattern(ast)
        return ast if ast.is_a?(Patterns::Base)

        case ast[0]
        when :send
          compile_pattern(ast[1]).send(ast[2], *ast[3..-1].map { |x| compile_pattern(x) })
        when :call
          @calls.fetch(ast[1]).call
        when :call_level
          builder = @precs.fetch(ast[1])
          level = builder.resolve_level(ast[2])
          builder.call_for(level)
        end
      end

      def finalize
        fst_call = @calls.values.first
        @grammar.finalize(fst_call.call)
      end

      def process
        mark = @marks[@index]
        @index += 1
        send("process_#{mark.name}", mark)
      end

      def process_all
        process while next_mark
      end

      def next_mark(pos = 0)
        @marks[@index + pos]
      end

      def shift
        @index += 1
      end

      def process_seq(mark)
        left = process
        right = process
        [:send, left, :>>, right]
      end

      def process_alt(mark)
        left = process
        right = process
        [:send, left, :|, right]
      end

      def process_opt(mark)
        base = process
        [:send, base, :maybe]
      end

      def process_star(mark)
        base = process
        [:send, base, :star]
      end

      def process_plus(mark)
        base = process
        [:send, base, :plus]
      end

      def process_pident(mark)
        name = process
        [:call, name]
      end

      def process_pident_level(mark)
        name = process
        level = process
        [:call_level, name, level]
      end

      def process_pstring(mark)
        text = process
        @grammar.str(text)
      end

      def process_pmark(mark)
        ident = process
        @grammar.mark(ident.to_sym)
      end

      def process_group(mark)
        process
      end

      def process_ident(mark)
        str = @string[mark.offset...next_mark.offset]
        shift
        str
      end

      def process_string(mark)
        str = @string[mark.offset...next_mark.offset]
        shift
        str
      end

      def process_number(mark)
        str = @string[mark.offset...next_mark.offset]
        shift
        str.to_i
      end

      def process_rule(mark)
        name = process
        pattern = process

        rule = @grammar._new_rule(name) {
          compile_pattern(pattern)
        }

        @calls[name] = proc { rule.call }
      end

      def process_prec_rule(mark)
        name = process

        builder = @precs[name] = Glush::Grammar::PrecBuilder.new(@grammar, name)
        while next_mark.name == :prec_branch
          proc {
            # We need this because of closures
            shift
            level = process
            pattern = process
            builder.add(level) { compile_pattern(pattern) }
          }.call
        end

        lowest_level = builder.resolve_level(nil)
        @calls[name] = proc { builder.call_for(lowest_level) }
      end

    end

    def self.parse(ebnf)
      parser = Glush::Parser.new(Grammar)
      parser.push_string(ebnf)
      parser.close
      raise "invalid ebnf" if !parser.final?
      marks = parser.flat_marks
      processor = Processor.new(marks, ebnf)
      processor.process_all
      processor.finalize
    end
  end
end

