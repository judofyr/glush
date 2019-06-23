module Glush
  class Parser
    State = Struct.new(:terminal, :rule_offset, :context) do
      def inspect
        "State(#{terminal.inspect} at #{rule_offset})"
      end
    end

    Mark = Struct.new(:name, :offset)

    # Represents a span where a rule was successfully completed
    RuleSpan = Struct.new(:rule, :left_offset)

    # Represents a position where a call was successfully completed
    CallPos = Struct.new(:call, :rule_offset)

    class RuleResult
      attr_reader :contexts

      def initialize
        @contexts = []
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
      end

      def add_rule_result(result)
        @rule_results << result
      end

      def add_left_context(context)
        @left_contexts << context
      end
    end

    class ParseError
      attr_reader :offset, :expected_tokens

      def initialize(offset, expected_tokens)
        @offset = offset
        @expected_tokens = expected_tokens
      end

      def valid?
        false
      end
    end

    class ParseSuccess
      def initialize(parser)
        @parser = parser
      end

      def marks
        @parser.flat_marks
      end

      def valid?
        true
      end
    end

    def initialize(grammar)
      @grammar = grammar
      @offset = 0
      @next_states = []
      @next_states << State.new(@grammar.start_call, -1, List.empty)
      @next_states << State.new(:success, -1, List.empty) if @grammar.empty?
      @callers = Hash.new { |h, k| h[k] = [] }

      @transitions = @grammar.transitions
    end

    def self.recognize_string?(grammar, string)
      parser = new(grammar)
      parser.push_string(string)
      parser.close
      parser.final?
    end

    def self.parse_string(grammar, string)
      new(grammar).parse_string(string)
    end

    def parse_string(input)
      input.each_codepoint do |codepoint|
        offset = @offset

        self << codepoint

        if @next_states.empty?
          expected_tokens = @failed_terminals
          return ParseError.new(offset, expected_tokens)
        end
      end

      offset = @offset

      close

      if final?
        ParseSuccess.new(self)
      else
        ParseError.new(offset, Set[nil])
      end
    end

    def push_string(input)
      input.each_codepoint { |codepoint| self << codepoint }
    end

    def close
      self << nil
    end

    def final?
      @final_states.any?
    end

    def <<(token)
      @rule_results = Hash.new { |h, k| h[k] = RuleResult.new }
      @call_results = Hash.new { |h, k| h[k] = CallResult.new }

      @states = @next_states
      @next_states = []
      @followed_states = Set.new
      @completed_conj = Hash.new { |h, k| h[k] = {} }
      @failed_terminals = Set.new
      @final_states = []
      @states.each do |state|
        follow(state, token)
      end
      @offset += 1
    end

    def follow(state, token)
      return if @followed_states.include?(state)
      @followed_states << state

      case state.terminal
      when Patterns::RuleCall
        rule = state.terminal.rule
        key = [rule, @offset]

        is_executed = @callers.has_key?(key)
        callers = @callers[key]
        callers << state

        return if is_executed

        rule.body.first_set.each do |fst_terminal|
          new_state = State.new(fst_terminal, @offset, List.empty)
          follow(new_state, token)
        end
      when Patterns::Rule
        rule = state.terminal

        if rule.guard
          if token && !rule.guard.match?(token)
            # Guard didn't match
            return
          end
        end

        key = [rule, state.rule_offset]

        # Freeze here to verify that no more callers will add themselves
        callers = @callers[key].freeze

        rule_span = RuleSpan.new(rule, state.rule_offset)

        is_executed = @rule_results.has_key?(rule_span)
        rule_result = @rule_results[rule_span]
        rule_result.add_context(state.context)

        return if is_executed

        grouped = callers.group_by { |x| CallPos.new(x.terminal, x.rule_offset) }

        grouped.each do |pos, call_states|
          is_executed = @call_results.has_key?(pos)
          call_result = @call_results[pos]
          call_result.add_rule_result(rule_result)

          call_states.each do |call_state|
            call_result.add_left_context(call_state.context)
          end

          next if is_executed

          context = List[call_result]
          follow_transitions(pos.call, pos.rule_offset, context, token)
        end
      when :success
        @final_states << state
      when Patterns::Conj::Finalizer
        finalizer = state.terminal
        conj = finalizer.id
        key = [conj, state.rule_offset]
        data = @completed_conj[key]

        if finalizer.type == :left
          data[:left] = true
          data[:context] = state.context
        else
          data[:right] = true
        end

        if data[:left] && data[:right]
          follow_transitions(conj, state.rule_offset, data[:context], token)
        end
      when Patterns::Marker
        mark = Mark.new(state.terminal.name, @offset)
        context = state.context.add(mark)
        follow_transitions(state.terminal, state.rule_offset, context, token)
      else
        if state.terminal.match?(token)
          accept_transitions(state.terminal, state.rule_offset, state.context)
        else
          @failed_terminals << state.terminal
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

    def reverse_marks
      # TODO: This code is a bit hackish
      marks = []

      queue = []
      queue << @final_states.map(&:context)

      until queue.empty?
        contexts = queue.pop

        if contexts.is_a?(Mark)
          marks << contexts
          next
        end

        if contexts.size != 1
          raise "ambigious"
        end

        contexts[0].each do |item|
          case item
          when Mark
            queue << item
          when CallResult
            queue << item.left_contexts
            rule_contexts = item.rule_results.flat_map { |r| r.contexts }
            queue << rule_contexts
          else
            raise "Unknown class: #{mark.class}"
          end
        end
      end
      marks
    end

    def flat_marks
      reverse_marks.reverse
    end
  end
end

