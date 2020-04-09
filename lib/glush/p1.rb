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
              result << [nil, rule_call, invoke_rule]
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
          .select { |context_rule, _, _| context_rule.nil? }
          .map { |_, _, invoke_rule| invoke_rule }
          .uniq
      }

      @indirect_rule_children = Hash.new { |h, k|
        h[k] = @builder.call_set(k)
          .select { |context_rule, _, _| @direct_rule_children[k].include?(context_rule) }
          .map { |_, cont_expr, invoke_rule| [cont_expr, invoke_rule] }
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
        enter_transitions(step)
        enter_calls(step)
        entries = step.entries
        return false if entries.empty?
        next_pos += 1
      end

      return entries.any? { |entry| entry.terminal == @final }
    end

    Entry = Struct.new(:terminal, :context_set)

    def initial_entries
      step = Step.new(0)
      context = Context.new(0, nil)
      context_set = Set[context]
      @expr_first.each do |expr|
        accept(step, expr, context_set)
      end
      enter_calls(step)
      step.entries
    end

    def accept(step, expr, context_set)
      if expr.is_a?(Expr::RuleCall)
        @call_set_with_conts[expr].each do |context_rule, cont_expr, invoke_rule|
          ctx = step.rule_contexts[invoke_rule]

          if context_rule
            ctx.add_callback(cont_expr, step.rule_contexts[context_rule])
          else
            ctx.merge_callback(cont_expr, context_set)
          end
        end

        if @in_tail_position[expr]
          @direct_rule_children[expr].each do |invoke_rule|
            step.pending_calls[invoke_rule].merge(context_set)
          end

          @indirect_rule_children[expr].each do |cont_expr, invoke_rule|
            ctx = step.rule_contexts[invoke_rule]
            ctx.merge_callback(cont_expr, context_set)
          end
        end
      else
        step.entries << Entry.new(expr, context_set)
      end
    end

    def enter_calls(step)
      step.rule_contexts.each do |rule, context|
        if @rule_term_first[rule].any?
          step.pending_calls[rule] << context
        end
      end

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
      attr_reader :position, :rule

      def initialize(position, rule)
        @position = position
        @rule = rule
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

      def initialize(position)
        @entries = Set.new
        @rule_contexts = Hash.new { |h, k| h[k] = Context.new(position, k) }
        @pending_calls = Hash.new { |h, k| h[k] = Set.new }
        @pending_transitions = Hash.new { |h, k| h[k] = Set.new }
      end
    end
  end
end
