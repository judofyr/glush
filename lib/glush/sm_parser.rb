module Glush
  class SMParser
    attr_reader :sm

    def initialize(grammar)
      @sm = grammar.state_machine

      initial_frame = Frame.new(Context.new(nil, List.empty))
      @sm.initial_states.each do |state|
        initial_frame.next_states << state
      end

      @initial_frames = [initial_frame]
    end

    def process_token(token, frames)
      step = Step.new(self, token)

      frames.each do |frame|
        step.process_frame(frame)
      end

      step
    end

    def recognize?(input)
      frames = @initial_frames

      input.each_codepoint do |codepoint|
        frames = process_token(codepoint, frames).next_frames
        return false if frames.empty?
      end

      process_token(nil, frames).accept?
    end

    class Context
      attr_reader :caller, :marks

      def initialize(caller, marks)
        @caller = caller
        @marks = marks
      end
    end

    class Frame
      attr_reader :next_states
      attr_reader :context

      def initialize(context)
        @context = context
        @next_states = Set.new
      end

      def caller
        @context.caller
      end

      def marks
        @context.marks
      end

      def copy
        Frame.new(@context)
      end
    end

    class MergeContext
      attr_reader :frame

      def initialize(caller)
        @visited_states = Set.new
        @context = Context.new(caller, List.empty)
        @frame = Frame.new(@context)
      end

      def try_next_state(state)
        !!@visited_states.add?(state)
      end
    end

    class Caller
      attr_reader :returns

      def initialize
        @returns = []
      end

      def add_return(context, next_state)
        @returns << [context, next_state]
      end
    end

    class Step
      attr_reader :next_frames

      def initialize(parser, token)
        @parser = parser
        @token = token
        @next_frames = []
        @callers = Hash.new { |h, k| h[k] = Caller.new }
        @merged_contexts = Hash.new { |h, k| h[k] = MergeContext.new(k) }
        @is_accept = false
      end

      def accept?
        @is_accept
      end

      def with_frame(context)
        frame = Frame.new(context)
        yield frame
        if frame.next_states.any?
          @next_frames << frame
        end
      end

      def process(frame, state)
        state.actions.each do |action|
          case action
          when StateMachine::TokenAction
            if action.pattern.match?(@token)
              frame.next_states << action.next_state
            end
          when StateMachine::MarkAction
            mark = [action.name, 0] # TODO: correct position
            mark_ctx = Context.new(frame.caller, frame.marks.add(mark))
            with_frame(mark_ctx) do |mark_frame|
              process(mark_frame, action.next_state)
            end
          when StateMachine::CallAction
            rule = action.rule

            is_executed = @callers.has_key?(rule)
            caller = @callers[rule]
            caller.add_return(frame.context, action.return_state)

            if !is_executed
              call_ctx = Context.new(caller, List.empty)
              with_frame(call_ctx) do |call_frame|
                @parser.sm.rule_first[rule].each do |first_state|
                  process(call_frame, first_state)
                end
              end
            end
          when StateMachine::ReturnAction
            rule = action.rule
            caller = frame.caller

            caller.returns.each do |context, next_state|
              is_pushed = @merged_contexts.has_key?(context.caller)
              merge_context = @merged_contexts[context.caller]

              if merge_context.try_next_state(next_state)
                process(merge_context.frame, next_state)
              end

              if !is_pushed
                @next_frames << merge_context.frame
              end
            end
          when StateMachine::AcceptAction
            @is_accept = true
          else
            raise "Unknown action: #{action}"
          end
        end
      end
      
      def process_frame(frame)
        with_frame(frame.copy) do |next_frame|
          frame.next_states.each do |state|
            process(next_frame, state)
          end
        end
      end
    end
  end
end

