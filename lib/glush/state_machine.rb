require 'set'

module Glush
  class StateMachine
    class State
      attr_reader :id, :actions

      def initialize(id)
        @id = id
        @actions = []
      end
    end

    MarkAction = Struct.new(:name, :next_state)
    TokenAction = Struct.new(:pattern, :next_state)
    CallAction = Struct.new(:rule, :return_state)
    ReturnAction = Struct.new(:rule)
    AcceptAction = :accept

    attr_reader :rules, :rule_first, :start_rule

    def initialize(grammar)
      @grammar = grammar
      @rules = []
      @rule_first = {}
      @state_mapping = Hash.new do |h, k|
        h[k] = State.new(h.size)
      end

      init_state = @state_mapping[:init]
      connect(init_state, @grammar.start_call)
      @state_mapping[@grammar.start_call].actions << AcceptAction

      if @grammar.empty?
        init_state.actions << AcceptAction
      end

      @initial_states = [init_state]

      grammar.rules.each do |rule|
        @rules << rule

        first_states = @rule_first[rule] = []

        rule.body.first_set.each do |fst_terminal|
          first_state = @state_mapping[rule]
          first_states << first_state
          connect(first_state, fst_terminal)
        end

        rule.body.each_pair do |a, b|
          connect(@state_mapping[a], b)
        end

        rule.body.last_set.each do |lst_terminal|
          state = @state_mapping[lst_terminal]
          state.actions << ReturnAction.new(rule)
        end
      end
    end

    def states
      @states ||= @state_mapping.values
    end

    def initial_states
      @initial_states
    end
    
    def connect(state, terminal)
      case terminal
      when Patterns::RuleCall
        return_state = @state_mapping[terminal]
        rule = terminal.rule
        action = CallAction.new(rule, return_state)
        state.actions << action
      when Patterns::Token
        next_state = @state_mapping[terminal]
        action = TokenAction.new(terminal, next_state)
        state.actions << action
      when Patterns::Marker
        next_state = @state_mapping[terminal]
        action = MarkAction.new(terminal.name, next_state)
        state.actions << action
      else
        raise "Unknown terminal: #{terminal.class}"
      end
    end

    def create_state(pattern)
      if @state_mapping.has_key?(pattern)
        return @state_mapping[pattern]
      end

      case pattern
      when Patterns::RuleCall
        next_states = []
        handler = CallHandler.new(pattern.rule, next_states)
      when Patterns::Rule
        handler = ReturnHandler.new(pattern)
      when Patterns::Token
        next_states = []
        handler = TokenHandler.new(pattern, next_states)
      else
        raise "unknown: #{pattern.class}"
      end

      id = @state_mapping.size
      state = @state_mapping[pattern] = State.new(id, handler)

      @grammar.transitions[pattern].each do |next_pattern|
        next_state = create_state(next_pattern)
        next_states << next_state if next_states
      end

      state
    end
  end
end

