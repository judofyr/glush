module Glush
  class P1
    class Builder
      EMPTY_SET = Set.new.freeze

      def initialize
        @nullable_fixpoint = FixpointBuilder.new(bottom: false)
        @rules_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
        @call_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
      end

      def nullable(expr)
        return false if expr.terminal?

        case expr
        when Expr::Alt
          nullable(expr.left) | nullable(expr.right)
        when Expr::Seq
          nullable(expr.left) & nullable(expr.right)
        when Expr::Plus
          nullable(expr.child)
        when Expr::Eps
          true
        when Expr::RuleCall
          @nullable_fixpoint.calculate(expr) do
            nullable(expr.rule.body)
          end
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

      def first_set(expr)
        return Set[expr] if expr.terminal?

        case expr
        when Expr::Alt
          first_set(expr.left) | first_set(expr.right)
        when Expr::Seq
          if nullable(expr.left)
            first_set(expr.left) | first_set(expr.right)
          else
            first_set(expr.left)
          end
        when Expr::Plus
          first_set(expr.child)
        when Expr::Eps
          EMPTY_SET
        when Expr::RuleCall
          Set[expr]
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

      def last_set(expr)
        return Set[expr] if expr.terminal?

        case expr
        when Expr::Alt
          last_set(expr.left) | last_set(expr.right)
        when Expr::Seq
          if nullable(expr.right)
            last_set(expr.left) | last_set(expr.right)
          else
            last_set(expr.right)
          end
        when Expr::Plus
          last_set(expr.child)
        when Expr::Eps
          EMPTY_SET
        when Expr::RuleCall
          Set[expr]
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

      Pair = Struct.new(:a, :b)

      def pair_set(expr)
        return EMPTY_SET if expr.terminal?

        case expr
        when Expr::Alt
          pair_set(expr.left) | pair_set(expr.right)
        when Expr::Seq
          result = Set.new
          result.merge(pair_set(expr.left))
          result.merge(pair_set(expr.right))
          last_set(expr.left).each do |a|
            first_set(expr.right).each do |b|
              result << Pair.new(a, b)
            end
          end
          result
        when Expr::Plus
          result = Set.new
          result.merge(pair_set(expr.child))
          last_set(expr.child).each do |a|
            first_set(expr.child).each do |b|
              result << Pair.new(a, b)
            end
          end
          result
        when Expr::Eps, Expr::RuleCall
          EMPTY_SET
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

      def call_set(rule_call)
        @call_fixpoint.calculate(rule_call) do
          result = Set[[nil, rule_call, rule_call.rule]]

          fst = first_set(rule_call.rule.body).grep(Expr::RuleCall)
          lst = last_set(rule_call.rule.body).grep(Expr::RuleCall)

          fst.each do |expr|
            call_set(expr).each do |context_rule, cont_expr, invoke_rule|
              result << [context_rule || rule_call.rule, cont_expr, invoke_rule]
            end
          end

          # Handle aliases
          (fst & lst).each do |expr|
            call_set(expr).each do |context_rule, cont_expr, invoke_rule|
              if context_rule.nil?
                result << [nil, rule_call, invoke_rule]
              end
            end
          end

          result
        end
      end

      def rules(expr)
        return EMPTY_SET if expr.terminal?

        case expr
        when Expr::Alt
          rules(expr.left) | rules(expr.right)
        when Expr::Seq
          rules(expr.left) | rules(expr.right)
        when Expr::Plus
          rules(expr.child)
        when Expr::Eps
          EMPTY_SET
        when Expr::RuleCall
          @rules_fixpoint.calculate(expr) do
            Set[expr.rule].merge(rules(expr.rule.body))
          end
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end
    end

    def initialize(expr)
      @expr = expr
      @builder = Builder.new
      @rules = @builder.rules(@expr)
      @transitions = Hash.new { |h, k| h[k] = [] }
      @rule_term_first = Hash.new
      @in_tail_position = Hash.new(false)

      # Build information about each rule:
      @rules.each do |rule|
        @builder.pair_set(rule.body).each do |pair|
          @transitions[pair.a] << pair.b
        end

        @rule_term_first[rule] = @builder.first_set(rule.body).reject { |p| p.is_a?(Expr::RuleCall) }

        @builder.last_set(rule.body).each do |p|
          @in_tail_position[p] = true
        end
      end

      @direct_rule_children = Hash.new { |h, k|
        h[k] = @builder.call_set(k)
          .select { |context_rule, _| context_rule.nil? }
          .map { |_, _, invoke_rule| invoke_rule }
          .uniq
      }

      @call_set_with_conts = Hash.new do |h, k|
        h[k] = @builder.call_set(k)
          .select { |_, cont_expr, _| @transitions[cont_expr].any? }
      end

      @final = Expr::Final.new

      @expr_nullable = @builder.nullable(@expr)
      @expr_first = @builder.first_set(@expr)
      @builder.last_set(@expr).each do |lst|
        @transitions[lst] << @final
      end
      @builder.pair_set(@expr).each do |pair|
        @transitions[pair.a] << pair.b
      end
    end

    def recognize?(input)
      if input.empty?
        return @expr_nullable
      end

      entries = initial_entries
      next_pos = 1

      input.each_codepoint do |token|
        step = Step.new(next_pos)
        process_entries(step, entries, token)
        enter_calls(step)
        entries = step.entries
        return false if entries.empty?
        next_pos += 1
      end

      return entries.any? { |expr, entry_set| expr == @final }
    end

    def initial_entries
      step = Step.new(0)
      entry_set = EntrySet.new
      @expr_first.each do |expr|
        accept(step, expr, entry_set)
      end
      enter_calls(step)
      step.entries
    end

    def accept(step, expr, entry_set)
      if expr.is_a?(Expr::RuleCall)
        @call_set_with_conts[expr].each do |context_rule, cont_expr, invoke_rule|
          if context_rule
            step.calls[invoke_rule] << Entry.new(cont_expr, step.calls[context_rule])
          else
            step.calls[invoke_rule] << Entry.new(cont_expr, entry_set)
          end
        end

        if @in_tail_position[expr]
          @direct_rule_children[expr].each do |invoke_rule|
            step.tail_calls[invoke_rule] << entry_set
          end
        end
      else
        step.terminals[expr].merge(entry_set)
      end
    end

    def enter_calls(step)
      step.tail_calls.each do |invoke_rule, entry_sets|
        entry_sets.each do |entry_set|
          step.calls[invoke_rule].merge(entry_set)
        end
      end

      step.calls.each do |rule, entry_set|
        @rule_term_first[rule].each do |term|
          step.terminals[term].merge(entry_set)
        end
      end
    end

    def process_entries(step, entries, token)
      entries.each do |expr, entry_set|
        if ExprMatcher.expr_matches?(expr, token)
          @transitions[expr].each do |next_expr|
            accept(step, next_expr, entry_set)
          end

          if @in_tail_position[expr]
            entry_set.each do |entry|
              @transitions[entry.expr].each do |next_expr|
                accept(step, next_expr, entry.entry_set)
              end
            end
          end
        end
      end
    end

    Entry = Struct.new(:expr, :entry_set)

    class EntrySet
      attr_reader :entries

      def initialize
        @entries = nil
        @borrowed = false
      end

      def <<(entry)
        if @entries.nil?
          @entries = Set.new
        elsif @borrowed
          @entries = @entries.dup
          @borrowed = false
        end

        @entries << entry
      end
      
      def merge(other)
        if @entries.nil?
          @entries = other.entries
          @borrowed = true
          return
        end

        if @borrowed
          @entries = @entries | other.entries
          @borrowed = false
        else
          @entries.merge(other.entries)
        end
      end

      def any?
        @entries.any?
      end

      def each(&blk)
        @entries.each(&blk)
      end

      def size
        if @entries
          @entries.size
        else
          0
        end
      end
    end

    class Step
      attr_reader :position, :terminals, :calls, :tail_calls

      def initialize(position)
        @position = position
        @terminals = Hash.new { |h, k| h[k] = EntrySet.new }
        @calls = Hash.new { |h, k| h[k] = EntrySet.new }
        @tail_calls = Hash.new { |h, k| h[k] = Set.new }
      end

      def entries
        terminals
      end
    end
  end
end
