module Glush
  class FixpointBuilder
    attr_reader :bottom

    def initialize(bottom:)
      @bottom = bottom
      @results = Hash.new { |h, k| h[k] = bottom }
      @running = false
    end

    def calculate(key, &blk)
      if !@running
        if @results.has_key?(key)
          # This was computed the previous time we calculated the fixpoint.
          return @results[key]
        end

        # Now let's kick everything off!
        @running = true
        @changed = true

        while @changed
          @changed = false
          @visited = Set.new
          value = calculate(key, &blk)
        end

        @running = false
        @changed = nil
        @visited = nil

        return value
      end

      if @visited.include?(key)
        # We've already visited this once.
        return @results[key]
      else
        @visited << key
        value = @results[key]
        new_value = yield

        if new_value != value
          @changed = true
          value = @results[key] = new_value
        end

        return value
      end
    end
  end
end