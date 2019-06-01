module Glush
  class Grammar
    attr_reader :rules, :start_call, :transitions, :owners

    def initialize(&blk)
      @rules = []

      result = instance_eval(&blk)
      if !result.is_a?(Patterns::RuleCall)
        raise "block must return a rule call"
      end

      @start_call = result.consume!

      _compute_empty
      _compute_transitions
    end

    def empty?
      @start_call.rule.body.empty?
    end

    def anytoken
      Patterns::Any.new
    end

    def anyascii
      Patterns::UTF8Char1.new.complete
    end

    def anyutf8
      Patterns::UTF8Char1.new.complete |
      Patterns::UTF8Char2.new.complete |
      Patterns::UTF8Char3.new.complete |
      Patterns::UTF8Char4.new.complete
    end

    def negtoken(tokens)
      Patterns::NegativeToken.new(tokens)
    end

    def token(token)
      Patterns::Token.new(token)
    end

    def str(text)
      text.bytes
        .map { |c| token(c) }
        .reduce { |a, b| a >> b }
    end

    def utf8inv(str)
      tokens = str.chars.map do |char|
        if char.bytesize > 1
          raise GrammarError, "inverse multi-byte UTF-8 not supported"
        end

        char.ord
      end

      negtoken(tokens) >> anyutf8
    end

    def eps
      Patterns::Eps.new
    end

    def mark(name)
      Patterns::Marker.new(name)
    end

    def sep_by(p, sep)
      sep_by1(p, sep).maybe
    end

    def sep_by1(p, sep)
      p >> (sep >> p).star
    end

    def end_by(p, sep)
      end_by1(p, sep).maybe
    end

    def end_by1(p, sep)
      (p >> sep).plus
    end

    def rule(name)
      old = method(name)
      rule = Patterns::Rule.new(name.to_s) { old.call }
      @rules << rule
      singleton_class.send(:remove_method, name)
      define_singleton_method(name) { rule.call }
      nil
    end

    private

    def _compute_empty
      empty_rules = Set.new

      begin
        before = empty_rules.size
        @rules.each do |rule|
          is_empty = rule.body.calculate_empty(empty_rules)
          empty_rules << rule if is_empty
        end
        after = empty_rules.size
      end while before != after
    end

    def _compute_transitions
      @transitions = Hash.new { |h, k| h[k] = [] }
      @owners = {}

      @rules.each do |rule|
        rule.body.each_pair do |a, b|
          @transitions[a] << b
          @owners[a] = @owners[b] = rule
        end

        rule.body.last_set.each do |lst|
          @transitions[lst] << rule
          @owners[lst] = rule
        end

        if !rule.body.empty? && rule.body.static?
          raise GrammarError, "rule #{rule.inspect} contains markers in empty position"
        end
      end

      @transitions[@start_call] << :success
    end
  end
end

