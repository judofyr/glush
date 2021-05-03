module Glush
  class P2

    class Builder
      EMPTY_SET = Set.new.freeze
      EMPTY_MARKS = [].freeze
      EMPTY_MARKS_SET = Set[EMPTY_MARKS].freeze

      MarkedExpr = Struct.new(:expr, :marks)
      MarkedTransition = Struct.new(:from, :to, :marks)

      def initialize
        @marks_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
        @rules_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
        @start_call_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
        @direct_call_fixpoint = FixpointBuilder.new(bottom: EMPTY_SET)
      end

      def marks(expr)
        return EMPTY_SET if expr.terminal?

        case expr
        when Expr::Alt
          marks(expr.left) + marks(expr.right)
        when Expr::Seq
          res = Set.new
          left = marks(expr.left)
          right = marks(expr.right)
          left.each do |l|
            right.each do |r|
              res << l + r
            end
          end
          res
        when Expr::Plus
          marks(expr.child)
        when Expr::Mark
          Set[[expr.name]]
        when Expr::Eps
          EMPTY_MARKS_SET
        when Expr::RuleCall
          @marks_fixpoint.calculate(expr) do
            marks(expr.rule.body)
          end
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

      def first_set(expr)
        return Set[MarkedExpr.new(expr, EMPTY_MARKS)] if expr.terminal?

        case expr
        when Expr::Alt
          first_set(expr.left) | first_set(expr.right)
        when Expr::Seq
          res = Set.new
          res.merge(first_set(expr.left))

          left_marks = marks(expr.left)
          right_fst = first_set(expr.right)
          left_marks.each do |l|
            right_fst.each do |r|
              res << MarkedExpr.new(r.expr, l + r.marks)
            end
          end

          res
        when Expr::Plus
          first_set(expr.child)
        when Expr::Eps, Expr::Mark
          EMPTY_SET
        when Expr::RuleCall
          Set[MarkedExpr.new(expr, EMPTY_MARKS)]
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

      def last_set(expr)
        return Set[MarkedExpr.new(expr, EMPTY_MARKS)] if expr.terminal?

        case expr
        when Expr::Alt
          last_set(expr.left) | last_set(expr.right)
        when Expr::Seq
          res = Set.new
          res.merge(last_set(expr.right))

          right_marks = marks(expr.right)
          left_lst = last_set(expr.left)
          right_marks.each do |r|
            left_lst.each do |l|
              res << MarkedExpr.new(l.expr, l.marks + r)
            end
          end

          res
        when Expr::Plus
          last_set(expr.child)
        when Expr::Eps, Expr::Mark
          EMPTY_SET
        when Expr::RuleCall
          Set[MarkedExpr.new(expr, EMPTY_MARKS)]
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

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
              result << MarkedTransition.new(a.expr, b.expr, a.marks + b.marks)
            end
          end
          result
        when Expr::Plus
          result = Set.new
          result.merge(pair_set(expr.child))
          last_set(expr.child).each do |a|
            first_set(expr.child).each do |b|
              result << MarkedTransition.new(a.expr, b.expr, a.marks + b.marks)
            end
          end
          result
        when Expr::Eps, Expr::RuleCall, Expr::Mark
          EMPTY_SET
        else
          raise NotImplementedError, "#{expr} not handled"
        end
      end

      DirectCall = Struct.new(:rule, :before_marks, :after_marks)

      def direct_call_set(rule)
        @direct_call_fixpoint.calculate(rule) do
          res = Set.new

          res << DirectCall.new(rule, EMPTY_MARKS_SET, EMPTY_MARKS_SET)

          fst = first_set(rule.body).select { |x| x.expr.is_a?(Expr::RuleCall) }
          lst = last_set(rule.body).select { |x| x.expr.is_a?(Expr::RuleCall) }

          alias_data = Hash.new { |h, k| h[k] = {start: Set.new, end: Set.new} }

          fst.each do |x|
            alias_data[x.expr][:start] << x.marks
          end

          lst.each do |x|
            alias_data[x.expr][:end] << x.marks
          end

          alias_data.each do |expr, data|
            if data[:start].any? && data[:end].any?
              direct_call_set(expr.rule).each do |call|
                before = call.before_marks.flat_map do |m1|
                  data[:start].map { |m2| m2 + m1 }
                end
                after = call.after_marks.flat_map do |m1|
                  data[:end].map { |m2| m1 + m2 }
                end
                res << DirectCall.new(call.rule, Set.new(before), Set.new(after))
              end
            end
          end

          res
        end
      end

      RecursiveCall = Struct.new(:invoke_rule, :cont_rule, :cont_expr, :before_marks, :after_marks)

      def start_call_set(rule)
        @start_call_fixpoint.calculate(rule) do
          res = Set[]
          fst = first_set(rule.body).select { |x| x.expr.is_a?(Expr::RuleCall) }

          fst.each do |inner_call|
            direct_call_set(inner_call.expr.rule).each do |direct_call|
              before_marks = direct_call.before_marks.map { |x| inner_call.marks + x }.to_set
              after_marks = direct_call.after_marks
              res << RecursiveCall.new(direct_call.rule, rule, inner_call.expr, before_marks, after_marks)
            end

            res.merge(start_call_set(inner_call.expr.rule))
          end
          res
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
        when Expr::Eps, Expr::Mark
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

    class StateBuilder
      attr_reader :tags
      attr_reader :states
      attr_reader :rules
      attr_reader :rule_start_states
      attr_reader :initial_states
      attr_reader :is_nullable
      attr_reader :rule_tags

      def initialize(expr)
        @tags = []

        @rules = nil
        @states = Hash.new do |h, k|
          h[k] = Expr::RuleCall === k ? CallState.new(k) : TerminalState.new(k)
        end
        @states[nil] = FinalState.instance
        @actions = Hash.new do |h, k|
          klass, *args = *k
          h[k] = klass.new(*args)
        end

        @rule_start_states = Hash.new { |h, k| h[k] = [] }
        @initial_states = []
        @is_nullable = nil

        build(expr)
        clear_unused_states
      end

      def each_state(&blk)
        @states.each_value(&blk)
      end

      def each_call_state
        each_state do |state|
          yield state if state.is_a?(CallState)
        end
      end

      private

      def marks_set(m)
        raise "unknown" if m.size != 1
        m.to_a[0]
      end

      def find_action(*args)
        @actions[args]
      end

      def build(expr)
        builder = Builder.new

        @rules = builder.rules(expr)

        last_exprs = Hash.new

        @rules.each do |rule|
          builder.pair_set(rule.body).each do |s|
            @states[s.from].add_transition(@states[s.to], s.marks)
          end

          builder.first_set(rule.body).each do |s|
            next if s.expr.is_a?(Expr::RuleCall)
            @rule_start_states[rule] << StateStart.new(@states[s.expr], s.marks)
          end
  
          builder.last_set(rule.body).each do |s|
            if last_exprs.has_key?(s.expr)
              raise "duplicate marks end marks"
            end

            last_exprs[s.expr] = s.marks
          end
        end

        builder.last_set(expr).each do |s|
          @states[s.expr].add_transition(FinalState.instance, s.marks)
        end

        builder.pair_set(expr).each do |t|
          @states[t.from].add_transition(@states[t.to], t.marks)
        end

        exprs = @rules.map(&:body) + [expr]
        exprs.each do |expr|
          expr.yield_self_and_children do |expr|
            if expr.is_a?(Expr::RuleCall)
              state = @states[expr]
              rule = expr.rule

              builder.direct_call_set(rule).each do |s|
                next if state.transitions.empty?
                if !@rule_start_states[s.rule].empty?
                  state.add_rule(s.rule)
                end

                action = find_action(DirectCallAction, s.rule, marks_set(s.before_marks), marks_set(s.after_marks))
                state.add_action(action)
              end

              builder.start_call_set(rule).each do |s|
                next_state = @states[s.cont_expr]
                next if next_state.transitions.empty?

                if !@rule_start_states[s.invoke_rule].empty?
                  state.add_rule(s.invoke_rule)
                end

                action = find_action(RecCallAction,
                  s.invoke_rule, s.cont_rule, next_state,
                  marks_set(s.before_marks),
                  marks_set(s.after_marks),
                )
                state.add_action(action)
              end

              if marks = last_exprs[expr]
                builder.direct_call_set(rule).each do |s|
                  if !@rule_start_states[s.rule].empty?
                    state.add_rule(s.rule)
                  end
                  action = find_action(TailCallAction, s.rule, marks_set(s.before_marks), marks_set(s.after_marks) + marks)
                  state.add_action(action)
                end
              end
            else
              if marks = last_exprs[expr]
                state = @states[expr]
                state.last_marks = marks
              end
            end
          end
        end

        @is_nullable = builder.marks(expr).any?

        builder.first_set(expr).each do |s|
          @initial_states << [@states[s.expr], nil]
        end
      end

      def clear_unused_states
        seen = Set.new

        visit = proc do |state|
          next if !seen.add?(state)

          case state
          when CallState
            state.transitions.each do |t|
              visit[t.state]
            end

            state.actions.each do |action|
              if action.is_a?(RecCallAction)
                visit[action.cont_state]
              end
            end
          when TerminalState
            state.transitions.each do |t|
              visit[t.state]
            end
          end
        end

        @initial_states.each do |state, tag|
          visit[state]
        end

        @rule_start_states.each do |rule, starts|
          starts.each do |start|
            visit[start.state]
          end
        end

        @states.delete_if do |_, state|
          !seen.include?(state)
        end
      end
      
      def dot_escape(str)
        str.gsub(/([\\"])/) { "\\#{$1}" }
      end

      public \
      def dump_dot(w)
        _node_id = Hash.new { |h, k| h[k] = "n#{h.size}" }
        node_id = proc { |obj| _node_id[obj.object_id] }

        w.puts "digraph glush {"
        rules.each do |rule|
          w.puts "#{node_id[rule]} [shape=box label=\"#{dot_escape(rule.name)}\"]"

          rule_start_states[rule].each do |state_start|
            w.puts "#{node_id[rule]} -> #{node_id[state_start.state]} [style=dotted]"
          end
        end

        initial = Object.new
        w.puts "#{node_id[initial]} [shape=point label=\"\"]"
        initial_states.each do |state, tag|
          w.puts "#{node_id[initial]} -> #{node_id[state]} [style=dotted]"
        end

        @actions.each_value do |action|
          case action
          when DirectCallAction
            w.puts "#{node_id[action]} [label=\"call #{dot_escape(action.invoke_rule.name)}\"]"
          when TailCallAction
            w.puts "#{node_id[action]} [label=\"tail #{dot_escape(action.invoke_rule.name)}\"]"
          when RecCallAction
            w.puts "#{node_id[action]} [label=\"start #{dot_escape(action.invoke_rule.name)}\n as #{dot_escape(action.cont_rule.name)}\"]"
            action.cont_state.transitions.each do |t|
              w.puts "#{node_id[action]} -> #{node_id[t.state]}"
            end
          end
        end

        states.each_value do |state|
          case state
          when CallState
            w.puts "#{node_id[state]} [label=\"#{dot_escape(state.rule_call.inspect)}\"]"
            state.actions.each do |action|
              w.puts "#{node_id[state]} -> #{node_id[action]} [style=dotted]"
            end
          when TerminalState
            per = "peripheries=2" if state.last_marks
            w.puts "#{node_id[state]} [shape=box #{per} label=\"#{dot_escape(state.terminal.inspect)}\"]"
          when FinalState
            w.puts "#{node_id[state]} [shape=doublecircle label=\"\"]"
            next
          end

          state.transitions.each do |t|
            w.puts "#{node_id[state]} -> #{node_id[t.state]}"
          end
        end
        w.puts "}"
      end
    end

    def initialize(expr)
      @expr = expr
      @state_builder = StateBuilder.new(expr)
    end

    StateTransition = Struct.new(:state, :marks) do
      def handler
        @handler ||= proc do |value, position|
          value + marks.map { |m| Mark.new(m, position) }
        end
      end
    end

    StateStart = Struct.new(:state, :marks) do
      def handler
        @handler ||= proc do |position|
          marks.map { |m| Mark.new(m, position) }
        end
      end
    end

    class CallAction
      attr_reader :invoke_rule, :before_marks, :after_marks

      def initialize(invoke_rule, before_marks, after_marks)
        @invoke_rule = invoke_rule
        @before_marks = before_marks
        @after_marks = after_marks
      end

      def handler
        @handler ||= proc do |before_value, before_pos, child_value, after_pos|
          before_value +
            before_marks.map { |m| Mark.new(m, before_pos) } +
            child_value +
            after_marks.map { |m| Mark.new(m, after_pos) }
        end
      end
    end

    class DirectCallAction < CallAction
    end

    class TailCallAction < CallAction
    end

    class RecCallAction
      attr_reader :invoke_rule, :cont_rule, :cont_state, :before_marks, :after_marks

      def initialize(invoke_rule, cont_rule, cont_state, before_marks, after_marks)
        @invoke_rule = invoke_rule
        @cont_rule = cont_rule
        @cont_state = cont_state
        @before_marks = before_marks
        @after_marks = after_marks
      end

      def handler
        @handler ||= proc do |before_pos, child_value, after_pos|
          before_marks.map { |m| Mark.new(m, before_pos) } +
            child_value +
            after_marks.map { |m| Mark.new(m, after_pos) }
        end
      end
    end

    class CallState
      attr_reader :rule_call
      attr_reader :rules
      attr_reader :actions
      attr_reader :transitions

      def initialize(rule_call)
        @rule_call = rule_call
        @rules = Set.new
        @actions = []
        @transitions = []
      end

      def inspect
        @rule_call.inspect
      end

      def add_rule(rule)
        @rules << rule
      end

      def add_action(action)
        @actions << action
      end

      def add_transition(state, marks)
        @transitions << StateTransition.new(state, marks)
      end
    end

    class TerminalState
      attr_reader :terminal
      attr_reader :transitions
      attr_accessor :last_marks

      def initialize(terminal)
        @terminal = terminal
        @transitions = []
        @last_marks = nil
      end

      def add_transition(state, handler)
        @transitions << StateTransition.new(state, handler)
      end

      def last_handler
        return if !@last_marks
        @last_handler ||= proc do |value, position|
          value + @last_marks.map { |m| Mark.new(m, position) }
        end
      end

      def inspect
        @terminal.inspect
      end
    end

    class FinalState
      def self.instance
        @instance ||= new
      end

      def transitions
        []
      end
    end

    def recognize?(input)
      return !parse(input).error?
    end

    def parse(input)
      if input.empty?
        return @state_builder.is_nullable ? ParseSuccess.new([]) : ParseError.new(0)
      end

      prev_step = initial_step()
      codepoints = input.codepoints
      codepoints.each_with_index do |token, pos|
        return ParseError.new(pos - 1) if prev_step.empty?
        step = Step.new(pos + 1)
        next_token = codepoints[pos + 1] || 0
        prev_step.each_active do |activation|
          process_activation(step, activation, token, next_token)
        end
        process_calls(step)
        prev_step = step
      end

      if prev_step.final_values.any?
        ParseSuccess.new(prev_step.final_values[0])
      else
        ParseError.new(codepoints.size)
      end
    end

    def parse!(input)
      parse(input).unwrap
    end

    def initial_step()
      step = Step.new(0)
      marks = []
      @state_builder.initial_states.each do |state, tag|
        accept(step, state, nil, marks)
      end
      process_calls(step)
      step
    end

    def accept(step, state, context, value)
      case state
      when CallState
        state.actions.each do |action|
          case action
          when TailCallAction
            inner_context = context_for(step, action.invoke_rule)
            handler = proc { |*args| action.handler.call(value, *args) }
            register_tail(inner_context, context, handler)
          when DirectCallAction
            inner_context = context_for(step, action.invoke_rule)
            handler = proc { |*args| action.handler.call(value, *args) }
            register_return(inner_context, context, state, handler)
          when RecCallAction
            inner_context = context_for(step, action.invoke_rule)
            ret_context = context_for(step, action.cont_rule)
            register_return(inner_context, ret_context, action.cont_state, action.handler)
          end
        end

        state.rules.each do |rule|
          step.calls << rule
        end
      when TerminalState
        step.enter_state(state, context, value)
      when FinalState
        step.final_values << value
      else
        raise "unknown state: #{state.class.inspect}"
      end
    end

    def process_activation(step, activation, token, next_token)
      state, context, value = *activation
      if ExprMatcher.expr_matches?(state.terminal, token, next_token)
        state.transitions.each do |t|
          accept(step, t.state, context, t.handler.call(value, step.position))
        end

        if last_handler = state.last_handler
          inner_value = last_handler.call(value, step.position)
          context.each_return do |cont_state, cont_context, handler|
            new_value = handler.call(context.position, inner_value, step.position)
            cont_state.transitions.each do |t|
              accept(step, t.state, cont_context, t.handler.call(new_value, step.position))
            end
          end
        end
      end
    end

    def process_calls(step)
      step.calls.each do |rule|
        inner_context = context_for(step, rule)
        @state_builder.rule_start_states[rule].each do |state_start|
          step.enter_state(state_start.state, inner_context, state_start.handler.call(step.position))
        end
      end
    end

    def register_return(context, cont_context, cont_state, handler)
      context.add_return(cont_state, cont_context, handler)
    end

    def register_tail(context, caller_context, handler)
      caller_context.each_return do |cont_state, cont_context, outer_handler|
        pos = caller_context.position
        combined_handler = proc do |before_pos, child_value, after_pos|
          inner_value = handler.call(before_pos, child_value, after_pos)
          outer_handler.call(pos, inner_value, after_pos)
        end
        context.add_return(cont_state, cont_context, combined_handler)
      end
    end

    FST = proc do |handlers, &blk|
      blk.call(handlers[0])
    end

    def context_for(step, rule)
      step.contexts[rule] ||= Context.new(rule, step.position, FST)
    end

    class Context
      attr_reader :position

      ReturnValue = Struct.new(:value, :handler)

      def initialize(rule, position, handler)
        @rule = rule
        @position = position
        @handler = handler
        @returns = Hash.new { |h, k| h[k] = [] }
      end

      def add_return(state, context, handler)
        @returns[[state, context]] << handler
      end

      def each_return
        @returns.each do |(state, context), handlers|
          @handler.call(handlers) do |handler|
            yield state, context, handler
          end
        end
      end
    end

    Activation = Struct.new(:state, :context, :value)

    class Step
      attr_reader :position, :calls, :contexts, :final_values

      def initialize(position)
        @position = position
        @active_set = Hash.new { |h, k| h[k] = [] }
        @final_values = []
        @contexts = Hash.new
        @calls = Set.new
      end

      def enter_state(state, context, value)
        raise TypeError, "expected Context" if context && !context.is_a?(Context)
        @active_set[[state, context]] << value
      end

      def each_active(&blk)
        @active_set.each do |(state, context), values|
          values.each do |value|
            yield Activation.new(state, context, value)
          end
        end
      end

      def empty?
        @active_set.empty?
      end
    end
  end
end
