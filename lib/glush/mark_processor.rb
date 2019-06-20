module Glush
  class MarkProcessor
    State = Struct.new(:marks, :string, :index)

    def setup_state(marks, string)
      @_glush_state = State.new(marks, string, 0)
    end

    def state
      @_glush_state or raise "state not available yet"
    end

    def string
      state.string
    end

    def next_mark(pos = 0)
      state.marks[state.index + pos]
    end

    def shift
      state.index += 1
    end

    def process
      mark = state.marks[state.index]
      shift
      send("process_#{mark.name}", mark)
    end

    def process_all
      process while next_mark
    end
  end
end

