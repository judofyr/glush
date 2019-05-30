module Glush
  class Parser
    State = Struct.new(:terminal, :rule_offset) do
      def inspect
        "State(#{terminal.inspect} at #{rule_offset})"
      end
    end

    def initialize(grammar)
      @grammar = grammar
      @offset = 0
      @states = []
      @states << State.new(@grammar.start_call, -1)
      @states << State.new(:success, -1) if @grammar.empty?
      @callers = {}
      @transitions = @grammar.transitions
    end

    def self.recognize_string?(grammar, string)
      parser = new(grammar)
      parser.push_string(string)
      parser.close
      parser.final?
    end

    def push_string(input)
      input.each_char { |char| self << char }
    end

    def close
      self << nil
    end

    def final?
      @is_final
    end

    def <<(token)
      @next_states = []
      @followed_states = Set.new
      @is_final = false
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
            new_state = State.new(fst_terminal, @offset)
            follow(new_state, token)
          end
        end
      when Patterns::Rule
        rule = state.terminal
        key = [rule, state.rule_offset]
        callers = @callers[key]
        callers.freeze
        callers.each do |call_state|
          @transitions[call_state.terminal].each do |next_terminal|
            new_state = State.new(next_terminal, call_state.rule_offset)
            follow(new_state, token)
          end
        end
      when :success
        @is_final = true
      else
        if state.terminal.match?(token)
          @transitions[state.terminal].each do |next_terminal|
            @next_states << State.new(next_terminal, state.rule_offset)
          end
        end
      end
    end
  end
end

