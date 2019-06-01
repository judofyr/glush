module Glush
  class Parser
    State = Struct.new(:terminal, :rule_offset, :context) do
      def inspect
        "State(#{terminal.inspect} at #{rule_offset})"
      end
    end

    Mark = Struct.new(:name, :offset)

    # Represents a span where a rule was successfully completed
    RuleSpan = Struct.new(:rule, :left_offset, :right_offset)

    # Represents a position where a call was successfully completed
    CallPos = Struct.new(:call, :rule_offset, :right_offset)

    class RuleResult
      attr_reader :contexts

      def initialize
        @contexts = []
        @followed = false
      end

      def try_follow
        if @followed
          false
        else
          @followed = true
        end
      end

      def add_context(context)
        @contexts << context
      end
    end

    class CallResult
      attr_reader :rule_results
      attr_reader :left_contexts

      def initialize
        @rule_results = []
        @left_contexts = []
        @followed = false
      end

      def try_follow
        if @followed
          false
        else
          @followed = true
        end
      end

      def add_rule_result(result)
        @rule_results << result
      end

      def add_left_context(context)
        @left_contexts << context
      end
    end

    def initialize(grammar)
      @grammar = grammar
      @offset = 0
      @states = []
      @states << State.new(@grammar.start_call, -1, List.empty)
      @states << State.new(:success, -1, List.empty) if @grammar.empty?
      @callers = {}

      @rule_results = Hash.new { |h, k| h[k] = RuleResult.new }
      @call_results = Hash.new { |h, k| h[k] = CallResult.new }

      @transitions = @grammar.transitions
    end

    def self.recognize_string?(grammar, string)
      parser = new(grammar)
      parser.push_string(string)
      parser.close
      parser.final?
    end

    def push_string(input)
      input.each_byte { |byte| self << byte }
    end

    def close
      self << nil
    end

    def final?
      @final_states.any?
    end

    def <<(token)
      @next_states = []
      @followed_states = Set.new
      @final_states = []
      @states.each do |state|
        follow(state, token)
      end
      @states = @next_states
      @offset += 1
    end

    def follow(state, token)
      return if @followed_states.include?(state)
      @followed_states << state

      case state.terminal
      when Patterns::RuleCall
        rule = state.terminal.rule
        key = [rule, @offset]

        if !@callers.has_key?(key)
          callers = @callers[key] = []
          first_call = true
        else
          callers = @callers[key]
        end

        callers << state

        if first_call
          rule.body.first_set.each do |fst_terminal|
            new_state = State.new(fst_terminal, @offset, List.empty)
            follow(new_state, token)
          end
        end
      when Patterns::Rule
        rule = state.terminal
        key = [rule, state.rule_offset]

        # Freeze here to verify that no more callers will add themselves
        callers = @callers[key].freeze

        rule_span = RuleSpan.new(rule, state.rule_offset, @offset)

        rule_result = @rule_results[rule_span]
        rule_result.add_context(state.context)

        return if !rule_result.try_follow

        grouped = callers.group_by { |x| CallPos.new(x.terminal, x.rule_offset, @offset) }

        grouped.each do |pos, call_states|
          call_result = @call_results[pos]
          call_result.add_rule_result(rule_result)

          call_states.each do |call_state|
            call_result.add_left_context(call_state.context)
          end

          next if !call_result.try_follow

          context = List[call_result]
          follow_transitions(pos.call, pos.rule_offset, context, token)
        end
      when :success
        @final_states << state
      else
        context = state.context
        if state.terminal.is_a?(Patterns::Marker)
          mark = Mark.new(state.terminal.name, @offset)
          context = context.add(mark)
        end

        if state.terminal.match?(token)
          if state.terminal.static?
            follow_transitions(state.terminal, state.rule_offset, context, token)
          else
            accept_transitions(state.terminal, state.rule_offset, context)
          end
        end
      end
    end

    def follow_transitions(terminal, rule_offset, context, token)
      @transitions[terminal].each do |next_terminal|
        new_state = State.new(next_terminal, rule_offset, context)
        follow(new_state, token)
      end
    end

    def accept_transitions(terminal, rule_offset, context)
      @transitions[terminal].each do |next_terminal|
        @next_states << State.new(next_terminal, rule_offset, context)
      end
    end

    ## Marks
    def each_mark(contexts = @final_states.map(&:context), &blk)
      if contexts.size != 1
        raise "ambigious"
      end

      contexts[0].each do |item|
        case item
        when Mark
          yield item
        when CallResult
          each_mark(item.left_contexts, &blk)
          rule_contexts = item.rule_results.flat_map { |r| r.contexts }
          each_mark(rule_contexts, &blk)
        else
          raise "Unknown class: #{mark.class}"
        end
      end

      self
    end

    def flat_marks
      result = []
      each_mark do |mark|
        result << mark
      end
      result
    end
  end
end

