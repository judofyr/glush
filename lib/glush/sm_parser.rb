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

    def recognize?(input)
      frames = @initial_frames
      position = 0

      input.each_codepoint do |codepoint|
        frames = process_token(codepoint, position, frames).next_frames
        return false if frames.empty?
        position += 1
      end

      process_token(nil, position, frames).accept?
    end

    def parse(input)
      frames = @initial_frames
      position = 0

      input.each_codepoint do |codepoint|
        frames = process_token(codepoint, position, frames).next_frames
        if frames.empty?
          return ParseError.new(position)
        end
        position += 1
      end

      last_step = process_token(nil, position, frames)

      if last_step.accept?
        ParseSuccess.new(last_step)
      else
        ParseError.new(position)
      end
    end

    def process_token(token, position, frames)
      step = Step.new(self, token, position)

      frames.each do |frame|
        step.process_frame(frame)
      end

      step
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

    class Caller
      def initialize
        @grouped = Hash.new { |h, k| h[k] = [] }
      end

      def each_return
        @grouped.each do |(ccaller, next_state), marks|
          yield ccaller, next_state, marks
        end
      end

      def add_return(context, next_state)
        @grouped[[context.caller, next_state]] << context.marks
      end
    end

    class Step
      attr_reader :next_frames

      def initialize(parser, token, position)
        @parser = parser
        @token = token
        @position = position

        @next_frames = []
        @callers = Hash.new { |h, k| h[k] = Caller.new }
        @returned_callers = Set.new
        @accepted_contexts = []
      end

      def accept?
        @accepted_contexts.any?
      end

      def marks
        @accepted_contexts[0].marks.to_a
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
            mark = Mark.new(action.name, @position)
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

            if @token && rule.guard && !rule.guard.match?(@token)
              next
            end

            caller = frame.caller

            # TODO: This means that we now ignore ambiguous returns
            should_process = !!@returned_callers.add?(caller)
            next if !should_process

            caller.each_return do |ccaller, next_state, marks|
              combined_marks = List.branched(marks).add_list(frame.marks)
              next_context = Context.new(ccaller, combined_marks)
              with_frame(next_context) do |next_frame|
                process(next_frame, next_state)
              end
            end
          when StateMachine::AcceptAction
            @accepted_contexts << frame.context
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

