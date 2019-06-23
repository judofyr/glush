module Glush
  class Grammar
    attr_reader :rules, :start_call, :transitions, :owners

    def initialize(&blk)
      @rules = []

      finalize(instance_eval(&blk)) if block_given?
    end

    def finalize(start_call)
      if !start_call.is_a?(Patterns::RuleCall)
        raise TypeError, "the main pattern must be a rule call"
      end

      @start_call = start_call.consume!
      _compute_empty
      _compute_transitions
      self
    end

    def empty?
      @start_call.rule.body.empty?
    end

    def anytoken
      token(nil)
    end

    def token(choice)
      Patterns::Token.new(choice)
    end

    def str(text)
      case text
      when String
        text.codepoints
          .map { |c| token(c) }
          .reduce { |a, b| a >> b }
      when Range
        a = text.begin
        b = text.end

        if a.size != 1 || b.size != 1
          raise GrammarError, "only single-character supported in range"
        end

        a_num = a.ord
        b_num = b.ord

        if b_num < a_num
          raise GrammarError, "invalid range"
        end

        token(a_num..b_num)
      else
        raise GrammarError, "unsupported type: #{text.inspect}"
      end
    end

    def inv(pattern)
      pattern.invert
    end

    def eps
      Patterns::Eps.new
    end

    def mark(name = :mark)
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

    def def_rule(name, guard: nil, &blk)
      rule = _new_rule(name.to_s, &blk)
      rule.guard = guard if guard
      define_singleton_method(name) { rule.call }
    end

    class PrecBuilder
      def initialize(grammar, name)
        @alternatives = Hash.new { |h, k| h[k] = [] }
        @rules = Hash.new do |h, level|
          h[level] = grammar._new_rule("#{name}^#{level}") { pattern_for(level) }
        end
      end

      def add(pattern_level, &blk)
        @alternatives[pattern_level] << blk
        self
      end

      def levels
        @levels ||= @alternatives.keys.sort
      end

      def pattern_for(level)
        pattern = @alternatives[level].map(&:call).reduce { |a, b| a | b }

        if next_level = levels.detect { |l| l > level }
          pattern |= call_for(next_level)
        end

        pattern
      end

      def resolve_level(level)
        level = 0 if level.nil?
        actual_level = levels.detect { |l| l >= level }
        if !actual_level
          raise GrammarError, "unknown precedence level: #{level}"
        end
        actual_level
      end

      def call_for(level)
        @rules[level].call
      end
    end

    def prec_rule(name, &blk)
      builder = PrecBuilder.new(self, name)
      yield builder

      define_singleton_method(name) do |level=nil|
        level = builder.resolve_level(level)
        builder.call_for(level)
      end
    end

    def _new_rule(name, &blk)
      Patterns::Rule.new(name, &blk)
        .tap { |rule| @rules << rule }
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
          @transitions[lst] << rule
        end

        if !rule.body.empty? && rule.body.static?
          raise GrammarError, "rule #{rule.inspect} contains markers in empty position"
        end
      end

      @transitions[@start_call] << :success
    end
  end
end

