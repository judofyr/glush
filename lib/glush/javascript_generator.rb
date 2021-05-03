require 'json'

module Glush
  class JavaScriptGenerator
    def initialize(expr, export: nil)
      @expr = expr
      @export = export
      @sb = P2::StateBuilder.new(expr)

      setup
    end

    def write(w)
      w << COMMON

      case @export
      when :esm
        w << "export {parse, recognize}\n"
      when :cjs
        w << "exports.parse = parse;\n"
        w << "exports.recognize = recognize;\n"
      end

      w << "var $isNullable = #{@sb.is_nullable};\n"
      write_marks_table(w)
      write_accept_funcs(w)
      write_trans_defs(w)
      write_terminal_matchers(w)
      write_rules(w)
      write_state_table(w)

      ## Write main function
      w << "$initial = [\n"
      @sb.initial_states.each do |state, _|
        idx = @state_idx.fetch(state)
        w << "  " << transition_string(state, [])
        w << ",\n"
      end
      w << "]\n"
    end

    def to_s
      io = String.new
      write(io)
      io
    end

    private

    class LocalVars
      def initialize(prefix, indent: "", &blk)
        @data = ""
        @indent = indent
        @prefix = prefix
        @vars = Hash.new
        @builder = blk
      end

      def [](key)
        if var = @vars[key]
          var
        else
          var = "#{@prefix}#{@vars.size}"
          @vars[key] = var
          @data << "#{@indent}var #{var} = #{@builder.call(key)};\n"
          var
        end
      end
       
      def data
        @data
      end
    end

    def rule_idx(rule)
      @rule_idx.fetch(rule)
    end

    def setup
      ## Set up rule index
      @rule_idx = Hash.new
      @rules = []
      @sb.rules.each do |rule|
        idx = @rule_idx[rule] = @rule_idx.size
        @rules << rule
      end

      ## Setup state index
      @state_idx = Hash.new
      @states = []
      @sb.each_state do |state|
        @state_idx[state] = @state_idx.size
        @states << state
      end

      ## Set up accept function names
      @accept_names = Hash.new { |h, k| h[k] = "accept#{@accept_names.size}" }

      @accept_states = Set.new

      @sb.each_state do |state|
        state.transitions.each do |t|
          @accept_states << t.state if t.state.is_a?(P2::CallState)
        end
      end

      @sb.initial_states.each do |state, _|
        if state.is_a?(P2::CallState)
          @accept_states << state
        end
      end

      ## Partition actions
      @action_partitions = Hash.new { |h, k| h[k] = Set.new }
      @action_refinement = PartitionRefinement.new

      @accept_states.each do |state|
        @action_refinement.observe(state.actions)
      end

      @action_refinement.partitions.each do |part|
        @accept_names[part]
      end

      @accept_states.each do |state|
        @accept_names[state]

        state.actions.each do |action|
          @action_partitions[state] << @action_refinement[action]
        end
      end

      ## Terminals
      @terminal_matchers = Hash.new
      @terminal_func = Hash.new
      @states.each do |state|
        if state.is_a?(P2::TerminalState)
          str = terminal_str(state.terminal, "t", "n")
          term_name = @terminal_func[str]
          if !term_name
            term_name = "term#{@terminal_func.size}"
            @terminal_func[str] = term_name
          end
          @terminal_matchers[state] = term_name
        end
      end

      ## Transition table
      @transition_defs = Hash.new { |h, k| h[k] = "trans#{h.size}" }
      @transition_table = Hash.new

      @sb.each_state do |state|
        @transition_table[state] = @transition_defs[state.transitions]
      end

      ## Marks table
      @marks_table = Hash.new { |h, k| h[k] = "marks#{h.size}" }
      @marks_table[[]]

      @sb.rule_start_states.each do |_, starts|
        starts.each do |start|
          @marks_table[start.marks]
        end
      end

      @states.each do |state|
        state.transitions.each do |t|
          @marks_table[t.marks]
        end

        if state.is_a?(P2::CallState)
          state.actions.each do |action|
            @marks_table[action.before_marks]
            @marks_table[action.after_marks]
          end
        end

        case state
        when P2::TerminalState
          if state.last_marks
            @marks_table[state.last_marks]
          end
        end
      end
    end


    def write_marks_table(w)
      @marks_table.each do |marks, name|
        w << "var #{name} = #{marks.to_json};\n"
      end
    end

    def write_rules(w)
      w << "$rules = [\n"
      @rules.each_with_index do |rule, idx|
        w << "  ["
        @sb.rule_start_states[rule].each_with_index do |start, idx|
          w << ", " if idx > 0
          state_idx = @state_idx.fetch(start.state)
          w << "makeStart(#{state_idx}, #{@marks_table.fetch(start.marks)})"
        end
        w << "],\n"
      end
      w << "]\n"
    end

    def write_accept_funcs(w)
      @action_refinement.partitions.each do |part|
        part_accept = @accept_names.fetch(part)
        w << "function #{part_accept}(step, context, value, state) {\n"
        w << "  // Partition\n"
        write_actions(w, part)
        w << "}\n"
      end

      ## Write accept functions
      @accept_states.each do |state|
        accept_name = @accept_names.fetch(state)
        w << "function #{accept_name}(step, context, value) {\n"
        write_call_state(w, state)
        w << "}\n"
      end
    end


    def write_call_state(w, state)
      w << "  // Call #{state.rule_call.name}\n"
      @action_partitions.fetch(state).each do |part|
        part_accept = @accept_names.fetch(part)
        state_ref = "$states[#{@state_idx.fetch(state)}]"
        w << "  #{part_accept}(step, context, value, #{state_ref});\n"
      end

      state.rules.each do |rule|
        w << "  startRule(step, #{rule_idx(rule)});\n"
      end
    end

    def write_actions(w, actions)
      contexts = LocalVars.new("ic", indent: "  ") do |rule|
        "contextFor(step, #{@rule_idx.fetch(rule)})"
      end

      buffer = ""

      actions.each do |action|
        case action
        when P2::DirectCallAction
          inner_context = contexts[action.invoke_rule]
          before_marks = @marks_table.fetch(action.before_marks)
          after_marks = @marks_table.fetch(action.after_marks)
          handler = "makeCallHandler(value, #{before_marks}, #{after_marks})"
          buffer << "  registerReturn(#{inner_context}, context, state, #{handler});\n"
        when P2::TailCallAction
          inner_context = contexts[action.invoke_rule]
          before_marks = @marks_table.fetch(action.before_marks)
          after_marks = @marks_table.fetch(action.after_marks)
          handler = "makeCallHandler(value, #{before_marks}, #{after_marks})"
          buffer << "  registerTail(#{inner_context}, context, #{handler});\n"
        when P2::RecCallAction
          inner_context = contexts[action.invoke_rule]
          cont_context = contexts[action.cont_rule]
          state_idx = @state_idx.fetch(action.cont_state)
          before_marks = @marks_table.fetch(action.before_marks)
          after_marks = @marks_table.fetch(action.after_marks)
          handler = "makeRecCallHandler(#{before_marks}, #{after_marks})"
          buffer << "  registerReturn(#{inner_context}, #{cont_context}, $states[#{state_idx}], #{handler});\n"
        end
      end

      w << contexts.data << buffer
    end

    def write_trans_defs(w)
      @transition_defs.each do |trans, name|
        w << "var #{name} = [\n"
        trans.each_with_index do |t, idx|
          w << "  " << transition_string(t.state, t.marks)
          w << ",\n"
        end
        w << "];\n"
      end
    end

    def write_terminal_matchers(w)
      ## Write terminal matchers
      @terminal_func.each do |str, name|
        w << "function #{name}(t, n) { return #{str}; }\n"
      end
    end

    def transition_string(state, marks)
      idx = @state_idx.fetch(state)
      case state
      when P2::TerminalState
        "makeTerminalTransition(#{idx}, #{@marks_table.fetch(marks)})"
      when P2::CallState
        accept_name = @accept_names.fetch(state)
        "makeTransition(#{@marks_table.fetch(marks)}, #{accept_name})"
      when P2::FinalState
        "makeFinalTransition(#{@marks_table.fetch(marks)})"
      else
        raise "unknown state: #{state.class}"
      end
    end

    def write_state_table(w)
      w << "var $states = [\n"
      @states.each_with_index do |state, idx|
        case state
        when P2::TerminalState
          w << "  makeState("
          transitions = @transition_defs.fetch(state.transitions)
          matcher = @terminal_matchers.fetch(state)
          last_marks = state.last_marks ? @marks_table.fetch(state.last_marks) : "null"
          w << "#{idx}, #{transitions}, #{matcher}, #{last_marks}"
          w << ")"
        when P2::CallState
          transitions = @transition_defs.fetch(state.transitions)
          w << "  makeState(#{idx}, #{transitions})"
        when P2::FinalState
          w << "  makeState(#{idx}, [])"
        else
          raise "unknown state: #{state.class}"
        end
        w << ",\n"
      end
      w << "];\n"
    end

    def terminal_str(terminal, ident, next_ident)
      case terminal
      when Expr::Equal
        "#{ident} == #{terminal.token}"
      when Expr::Greater
        "#{ident} > #{terminal.token}"
      when Expr::Less
        "#{ident} < #{terminal.token}"
      when Expr::Any
        "true"
      when Expr::Conj
        "(%s) && (%s)" % [
          terminal_str(terminal.left, ident, next_ident),
          terminal_str(terminal.right, ident, next_ident),
        ]
      when Expr::Alt
        "(%s) || (%s)" % [
          terminal_str(terminal.left, ident, next_ident),
          terminal_str(terminal.right, ident, next_ident),
        ]
      when Expr::WithNext
        raise "nested WithNext not allowed" if next_ident.nil?
        "(%s) && (%s)" % [
          terminal_str(terminal.current_expr, ident, next_ident),
          terminal_str(terminal.next_expr, next_ident, nil),
        ]
      else
        raise "unknown terminal: #{terminal.class}"
      end
    end

    COMMON = <<~JS
      function makeTerminalAccept(idx) {
        function accept(step, context, value) {
          var state = $states[idx];
          var key = context.key + idx;
          step.activeSet[key] = {
            state: state,
            context: context,
            value: value
          };
        }
        return accept;
      }

      function makeTerminalTransition(idx, marks) {
        return makeTransition(marks, makeTerminalAccept(idx))
      }

      function makeFinalTransition(marks) {
        function accept(step, context, value) {
          step.finalValue = value;
        }

        return makeTransition(marks, accept);
      }

      function makeTransition(marks, accept) {
        function handler(value, pos) {
          var result = value.slice();
          for (var i = 0; i < marks.length; i++) {
            result.push([pos, marks[i]]);
          }
          return result;
        }

        return {
          handler: handler,
          accept: accept,
        }
      }

      function makeStart(idx, marks) {
        function handler(pos) {
          var result = [];
          for (var i = 0; i < marks.length; i++) {
            result.push({position: pos, name: marks[i]});
          }
          return result;
        }

        return {
          handler: handler,
          accept: makeTerminalAccept(idx)
        }
      }

      function makeState(idx, transitions, matcher, lastMarks) {
        var lastHandler;
        if (lastMarks) {
          lastHandler = function(value, pos) {
            var result = value.slice();
            for (var i = 0; i < lastMarks.length; i++) {
              result.push({position: pos, name: lastMarks[i]});
            }
            return result;
          }
        }

        return {
          key: "s"+idx,
          transitions: transitions,
          matcher: matcher,
          lastHandler: lastHandler,
        }
      }

      function makeCallHandler(value, beforeMarks, afterMarks) {
        return function(beforePos, innerValue, afterPos) {
          var result = value.slice();

          for (var i = 0; i < beforeMarks.length; i++) {
            result.push({position: beforePos, name: beforeMarks[i]});
          }

          result.push.apply(result, innerValue);

          for (var i = 0; i < afterMarks.length; i++) {
            result.push({position: afterPos, name: afterMarks[i]});
          }

          return result;
        }
      }

      function makeRecCallHandler(beforeMarks, afterMarks) {
        return function(beforePos, innerValue, afterPos) {
          var result = [];

          for (var i = 0; i < beforeMarks.length; i++) {
            result.push({position: beforePos, name: beforeMarks[i]});
          }

          result.push.apply(result, innerValue);

          for (var i = 0; i < afterMarks.length; i++) {
            result.push({position: afterPos, name: afterMarks[i]});
          }

          return result;
        }
      }

      function newStep(pos) {
        return {
          position: pos,
          contexts: {},
          rules: {},
          activeSet: {},
        }
      }

      function contextFor(step, ruleIdx) {
        var key = "r" + ruleIdx + "p" + step.position;
        var context = step.contexts[key];
        if (!context) {
          step.contexts[key] = context = {
            key: key,
            position: step.position,
            returnSet: {}
          }
        }
        return context;
      }

      function done(step, context, value) {
        step.finalValue = value;
      }

      function startRule(step, ruleIdx) {
        var key = ruleIdx;
        step.rules[key] = $rules[ruleIdx];
      }

      function startCalls(step) {
        for (var key in step.rules) {
          if (!step.rules.hasOwnProperty(key)) continue;
          var transitions = step.rules[key];
          var context = contextFor(step, key);
          for (var j = 0; j < transitions.length; j++) {
            var t = transitions[j];
            var value = t.handler(step.position);
            t.accept(step, context, value);
          }
        }
      }

      function combineHandlers(pos, outerHandler, handler) {
        return function combinedHandler(beforePos, childValue, afterPos) {
          var innerValue = handler(beforePos, childValue, afterPos);
          return outerHandler(pos, innerValue, afterPos);
        }
      }

      function registerTail(context, callerContext, handler) {
        var pos = callerContext.position;
        var returns = callerContext.returnSet;
        for (var key in returns) {
          if (!returns.hasOwnProperty(key)) continue;
          var ret = returns[key];
          var outerHandlers = ret.handlers;
          for (var j = 0; j < outerHandlers.length; j++) {
            var outerHandler = outerHandlers[j];
            var combinedHandler = combineHandlers(pos, outerHandler, handler);
            registerReturn(context, ret.context, ret.state, combinedHandler);
          }
        }
      }

      function registerReturn(context, contContext, contState, handler) {
        var key = contState.key + contContext.key;
        var value = context.returnSet[key];
        if (!value) {
          value = context.returnSet[key] = {
            state: contState,
            context: contContext,
            handlers: [],
          }
        }
        value.handlers.push(handler);
      }

      function processActivation(activation, step, token, nextToken) {
        var matcher = activation.state.matcher;
        var value = activation.value;
        var didMatch = matcher(token, nextToken);
        if (!didMatch) return;

        var ts = activation.state.transitions;
        for (var i = 0; i < ts.length; i++) {
          var t = ts[i];
          var newValue = t.handler(value, step.position);
          t.accept(step, activation.context, newValue);
        }

        var lastHandler = activation.state.lastHandler;
        if (lastHandler) {
          var innerValue = lastHandler(value, step.position);
          var returns = activation.context.returnSet;
          for (var key in returns) {
            if (!returns.hasOwnProperty(key)) continue;
            var ret = returns[key];
            var handler = ret.handlers[0]
            var retValue = handler(activation.context.position, innerValue, step.position);
            var ts = ret.state.transitions;
            for (var j = 0; j < ts.length; j++) {
              var t = ts[j];
              var newValue = t.handler(retValue, step.position);
              t.accept(step, ret.context, newValue);
            }
          }
        }
      }

      function parse(str) {
        if (str.length === 0) {
          return $isNullable ? {type: 'success', marks: []} : {type: 'error', position: 0}
        }

        var step = newStep(0);
        var initialContext = { key: "root", position: 0 };

        for (var i = 0; i < $initial.length; i++) {
          var t = $initial[i];
          var value = t.handler([], 0);
          t.accept(step, initialContext, value);
        }

        startCalls(step);

        var pos = 0;
        while (pos < str.length) {
          var active = step.activeSet;
          var nextStep = newStep(pos + 1);
          var token = str.codePointAt(pos);
          var nextPos = pos + (token >= 0xFFFF ? 2 : 1)
          var nextToken = str.codePointAt(nextPos) || 0;
          var isEmpty = true;
          for (var key in active) {
            if (!active.hasOwnProperty(key)) continue;
            var activation = active[key];
            processActivation(activation, nextStep, token, nextToken);
            isEmpty = false;
          }
          if (isEmpty) {
            return {type: 'error', position: pos-1}
          }
          step = nextStep;
          startCalls(step);
          pos = nextPos;
        }

        if (step.finalValue) {
          return {type: 'success', marks: step.finalValue}
        } else {
          return {type: 'error', position: str.length}
        }
      }

      function recognize(str) {
        var result = parse(str);
        return result.type === 'success';
      }
    JS
  end
end
