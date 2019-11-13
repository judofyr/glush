module Glush
  class P1
    class Builder
      EMPTY_SET = Set.new.freeze

      def initialize
        @nullable_fixpoint = FixpointBuilder.new(bottom: false)
        @enter_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
        @rules_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
        @alias_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
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
        when Expr::Eps, Expr::Marker
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
        when Expr::Eps, Expr::Marker
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
        when Expr::Eps, Expr::Marker
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
        when Expr::Eps, Expr::RuleCall, Expr::Marker
          EMPTY_SET
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

      def enter_set(rule_call)
        @enter_fixpoint.calculate(rule_call) do
          result = Set[]
          first_set(rule_call.rule.body).each do |p|
            if p.is_a?(Expr::RuleCall)
              result << p
              result.merge(enter_set(p))
            end
          end
          result
        end
      end

      def alias_set(rule_call)
        @alias_fixpoint.calculate(rule_call) do
          result = Set[rule_call.rule]
          (first_set(rule_call.rule.body) & last_set(rule_call.rule.body)).each do |expr|
            if expr.is_a?(Expr::RuleCall)
              result.merge(alias_set(expr))
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
        when Expr::Eps, Expr::Marker
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

      input.each_codepoint do |token|
        step = Step.new
        process_entries(step, entries, token)
        enter_transitions(step)
        enter_calls(step)
        entries = step.entries
        return false if entries.empty?
      end

      return entries.any? { |entry| entry.terminal == @final }
    end

    Entry = Struct.new(:terminal, :context_set)

    def initial_entries
      step = Step.new
      context = Context.new
      context_set = Set[context]
      @expr_first.each do |expr|
        accept(step, expr, context_set)
      end
      enter_calls(step)
      step.entries
    end

    def accept(step, expr, context_set)
      if expr.is_a?(Expr::RuleCall)
        # Recursive calls:
        @builder.enter_set(expr).each do |call|
          @builder.alias_set(call).each do |rule|
            ctx = step.rule_contexts[rule]
            ctx.add_callback(call, ctx)
            step.pending_calls[rule] << ctx
          end
        end

        if !@transitions[expr].empty?
          # Regular call:
          @builder.alias_set(expr).each do |rule|
            ctx = step.rule_contexts[rule]
            ctx.merge_callback(expr, context_set)
            step.pending_calls[rule] << ctx
          end
        end

        if @in_tail_position[expr]
          # Tail call invocation:
          @builder.alias_set(expr).each do |rule|
            step.pending_calls[rule].merge(context_set)
          end
        end
      else
        step.entries << Entry.new(expr, context_set)
      end
    end

    def enter_calls(step)
      step.pending_calls.each do |rule, context_set|
        @rule_term_first[rule].each do |expr|
          step.entries << Entry.new(expr, context_set)
        end
      end
    end

    def process_entries(step, entries, token)
      entries.each do |entry|
        if ExprMatcher.expr_matches?(entry.terminal, token)
          step.pending_transitions[entry.terminal].merge(entry.context_set)

          if @in_tail_position[entry.terminal]
            entry.context_set.each do |context|
              context.each do |rule_call, context_set|
                step.pending_transitions[rule_call].merge(context_set)
              end
            end
          end
        end
      end
    end

    def enter_transitions(step)
      step.pending_transitions.each do |expr, context_set|
        @transitions[expr].each do |next_expr|
          accept(step, next_expr, context_set)
        end
      end
    end

    class Context
      def initialize
        @callback_sets = Hash.new { |h, k| h[k] = Set.new }
      end

      def merge_callback(rule_call, context_set)
        @callback_sets[rule_call].merge(context_set)
      end

      def add_callback(rule_call, parent_context)
        @callback_sets[rule_call] << parent_context
      end

      def each(&blk)
        @callback_sets.each(&blk)
      end
    end

    class Step
      attr_reader :entries, :pending_calls, :rule_contexts, :pending_transitions

      def initialize
        @entries = Set.new
        @rule_contexts = Hash.new { |h, k| h[k] = Context.new }
        @pending_calls = Hash.new { |h, k| h[k] = Set.new }
        @pending_transitions = Hash.new { |h, k| h[k] = Set.new }
      end
    end
  end
end
