module Glush
  class EBNF
    Grammar = ::Glush::Grammar.new {
      def_rule :ebnf_rule do
        mark(:rule) >> ident >> ign >> ebnf_rule_sep >> ign >> ebnf_pattern
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
        p.add(10) { mark(:pstring) >> ebnf_str }
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

        @main_rule_name = nil
        @rule_body = {}
        @rules = Hash.new { |h, k|
          h[k] = @grammar._new_rule(k) {
            @rule_body.fetch(k)
          }
        }
      end

      def finalize
        @grammar.finalize(@rules[@main_rule_name].call)
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
        left >> right
      end

      def process_alt(mark)
        left = process
        right = process
        left | right
      end

      def process_opt(mark)
        base = process
        base.maybe
      end

      def process_star(mark)
        base = process
        base.star
      end

      def process_plus(mark)
        base = process
        base.plus
      end

      def process_pident(mark)
        name = process
        @rules[name].call
      end

      def process_pstring(mark)
        text = process
        @grammar.str(text)
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

      def process_rule(mark)
        name = process
        pattern = process
        @main_rule_name ||= name
        @rule_body[name] = pattern
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

