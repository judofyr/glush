module Glush
  class Grammar
    attr_reader :rules, :start_call, :transitions

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

    def str(text)
      text.chars
        .map { |c| Patterns::Char.new(c) }
        .reduce { |a, b| a >> b }
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

      @rules.each do |rule|
        rule.body.each_pair do |a, b|
          @transitions[a] << b
        end

        rule.body.last_set.each do |lst|
          if lst.is_a?(Patterns::Marker)
            raise GrammarError, "rule #{rule.inspect} cannot have #{lst.inspect} in final position"
          end

          @transitions[lst] << rule
        end
      end

      @transitions[@start_call] << :success
    end
  end
end

