module Glush
  class EBNF
    Grammar = ::Glush::Grammar.new {
      def_rule :ebnf_rule do
        mark(:rule) >> ident >> ign >> ebnf_rule_sep >> ign >> (str("|") >> ign).maybe >> ebnf_pattern >> (ign >> guard).maybe |
        mark(:prec_rule) >> ident >> ign >> ebnf_rule_sep >> ign >> ebnf_prec_branches >> (ign >> guard).maybe
      end

      def guard
        str("@guard(") >> ign >> mark(:guard) >> ebnf_pattern >> ign >> str(")")
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

      def prefix_pattern(r, level=0)
        str(r) >> ign >> ebnf_pattern(level)
      end

      prec_rule :ebnf_pattern do |p|
        p.add(1)  { mark(:alt) >> ebnf_pattern(1) >> ign >> str("|") >> ign >> ebnf_pattern(2) }
        p.add(2)  { mark(:seq) >> ebnf_pattern(2) >> ign >> (str(",") >> ign).maybe >> ebnf_pattern(3) }

        p.add(3)  { mark(:opt) >> postfix_pattern("?", 4) }
        p.add(3)  { mark(:plus) >> postfix_pattern("+", 4) }
        p.add(3)  { mark(:star) >> postfix_pattern("*", 4) }

        p.add(4)  { mark(:inv) >> prefix_pattern("!", 5) }

        p.add(10) { mark(:group) >> braced_pattern("(", ")") }
        p.add(10) { mark(:opt)   >> braced_pattern("[", "]") }
        p.add(10) { mark(:star)  >> braced_pattern("{", "}") }

        p.add(10) { mark(:pident) >> ident }
        p.add(10) { mark(:pident_level) >> ident >> str("^") >> number }
        p.add(10) { mark(:pstring) >> ebnf_str }
        p.add(10) { mark(:pmark) >> str("$") >> ident }
        p.add(10) { mark(:prange) >> ebnf_str >> ign >> str("..") >> ign >> ebnf_str }
      end

      def_rule :ebnf_prec_branches do
        sep_by1(
          mark(:prec_branch) >> number >> str("|") >> ign >> ebnf_pattern,
          ign
        )
      end

      ## Whitespace

      def ign
        (whitespace | comment).star
      end

      def whitespace
        str(" ") | str("\n")
      end

      def comment
        str("#") >> inv(str("\n")).star >> str("\n")
      end

      def str_char(close_char)
        escape_char |
        inv(str(close_char) | str("\\"))
      end

      ESCAPE_CHARS = %w[b f n r t v 0 ' " \\]
        .map { |char| str(char) }
        .reduce { |a, b| a | b }

      def escape_char
        mark(:escape_lit) >> str("\\") >> ESCAPE_CHARS >> mark |
        mark(:escape_unicode) >> str("\\u") >> unicode_hex >> mark
      end

      def unicode_hex
        mark >> hex >> hex >> hex >> hex >> mark |
        str("{") >> mark >> hex.plus >> mark >> str("}")
      end

      def hex
        str("0".."9") | str("a".."f") | str("A".."F")
      end

      def ebnf_str
        str("\"") >> mark(:string) >> str_char("\"").star >> mark >> str("\"") |
        str("'")  >> mark(:string) >> str_char("'").star >> mark >> str("'")
      end

      def ident_fst
        str("a".."z") | str("A".."Z") | str("_")
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

    class Processor < MarkProcessor
      attr_reader :grammar

      def initialize(marks, string)
        setup_state(marks, string)
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
        when :inv
          @grammar.inv(compile_pattern(ast[1]))
        when :call_level
          builder = @precs.fetch(ast[1])
          level = builder.resolve_level(ast[2])
          builder.call_for(level)
        end
      end

      def finalize
        fst_call = @calls.values.first
        @grammar.finalize(fst_call.call)
        @grammar
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
        case name
        when "any"
          @grammar.anytoken
        else
          [:call, name]
        end
      end

      def process_pident_level(mark)
        name = process
        level = process
        [:call_level, name, level]
      end

      def process_inv(mark)
        base = process
        [:inv, base]
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
        str = string[mark.position...next_mark.position]
        shift
        str
      end

      ESCAPE_CHAR_MAPPING = {
        "b" => "\b",
        "f" => "\f",
        "n" => "\n",
        "r" => "\r",
        "t" => "\t",
        "v" => "\v",
        "0" => "\0",
        "'" => "'",
        "\"" => "\"",
        "\\" => "\\",
      }

      def process_string(mark)
        result = String.new
        while true
          result << string[mark.position...next_mark.position]
          case next_mark.name
          when :escape_lit
            slash_start = next_mark; shift
            char = string[slash_start.position+1]
            result << ESCAPE_CHAR_MAPPING.fetch(char)
            mark = next_mark; shift
          when :escape_unicode
            shift
            hex_start = next_mark; shift
            hex_stop = next_mark; shift
            hex = string[hex_start.position...hex_stop.position]
            char = hex.to_i(16).chr(Encoding::UTF_8)
            result << char
            mark = next_mark; shift
          when :mark
            shift
            break
          end
        end
        result
      end

      def process_number(mark)
        str = string[mark.position...next_mark.position]
        shift
        str.to_i
      end

      def process_prange(mark)
        str1 = process
        str2 = process
        @grammar.str(str1..str2)
      end

      def process_rule(mark)
        name = process
        pattern = process

        if next_mark && next_mark.name == :guard
          shift
          guard = process
          guard_pattern = compile_pattern(guard)
        end

        rule = @grammar._new_rule(name) {
          compile_pattern(pattern)
        }
        rule.guard = guard_pattern if guard_pattern

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

    Parser = Glush::DefaultParser.new(Grammar)

    def self.create_grammar(ebnf)
      result = Parser.parse(ebnf).unwrap
      marks = result.marks
      processor = Processor.new(marks, ebnf)
      processor.process_all
      processor.finalize
    end

    def self.create_parser(ebnf)
      DefaultParser.new(create_grammar(ebnf))
    end
  end
end

