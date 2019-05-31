module Glush
  class Parser
    State = Struct.new(:terminal, :rule_offset, :marks) do
      def inspect
        "State(#{terminal.inspect} at #{rule_offset})"
      end
    end

    class MarkList
      def self.empty
        @empty ||= new
      end

      def initialize(marks = [])
        @marks = marks
      end

      def add(mark)
        MarkList.new(@marks + [mark])
      end

      def each(&blk)
        @marks.each(&blk)
      end
    end

    Mark = Struct.new(:name, :offset)
    RuleMark = Struct.new(:rule, :left_offset, :right_offset)

    def initialize(grammar)
      @grammar = grammar
      @offset = 0
      @states = []
      @states << State.new(@grammar.start_call, -1, MarkList.empty)
      @states << State.new(:success, -1, MarkList.empty) if @grammar.empty?
      @callers = {}
      @rule_final_states = Hash.new { |h, k| h[k] = [] }
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
            new_state = State.new(fst_terminal, @offset, MarkList.empty)
            follow(new_state, token)
          end
        end
      when Patterns::Rule
        rule = state.terminal
        key = [rule, state.rule_offset]
        callers = @callers[key]
        callers.freeze

        rule_mark = RuleMark.new(rule, state.rule_offset, @offset)
        @rule_final_states[rule_mark] << state

        callers.each do |call_state|
          @transitions[call_state.terminal].each do |next_terminal|
            new_state = State.new(next_terminal, call_state.rule_offset, call_state.marks.add(rule_mark))
            follow(new_state, token)
          end
        end
      when Patterns::Marker
        mark = Mark.new(state.terminal.name, @offset)
        @transitions[state.terminal].each do |next_terminal|
          new_state = State.new(next_terminal, state.rule_offset, state.marks.add(mark))
          follow(new_state, token)
        end
      when :success
        @final_states << state
      else
        if state.terminal.match?(token)
          @transitions[state.terminal].each do |next_terminal|
            @next_states << State.new(next_terminal, state.rule_offset, state.marks)
          end
        end
      end
    end

    ## Marks
    def each_flat_mark(states = @final_states, &blk)
      if states.size != 1
        raise "ambigious"
      end

      states[0].marks.each do |mark|
        case mark
        when Mark
          yield mark
        when RuleMark
          rule_states = @rule_final_states.fetch(mark)
          each_flat_mark(rule_states, &blk)
        end
      end

      self
    end

    def flat_marks(states = @final_states)
      result = []
      each_flat_mark do |mark|
        result << mark
      end
      result
    end
  end
end

