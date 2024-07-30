# frozen_string_literal: true

module ExcADG::Tui
  # collection of low-level {Block} formatting methods;
  # most methods mutate an object they called for to avoid re-copying data each time;
  # the module isn't expected to be used directly and exists just to de-couple
  # formatting methods and basic blocks positioning (see {Block});
  # all methods could be chained: `block.v_pad!(10).h_pad!(2).box!`
  module Format
    # add horizontal padding to the block
    # @param size number of spaces to add
    def h_pad! size
      @array.collect! { |row|
        "#{' ' * size}#{row}#{' ' * size}"
      }
      @width += size * 2
      self
    end

    # add vertical padding to the block
    # @param size number of spaces to add
    def v_pad! size
      filler = ' ' * @width
      size.times {
        self >> filler
        self << filler
      }
      self
    end

    # adds spaces around the block
    # @param size number of spaces to add
    def pad! size
      v_pad! size
      h_pad! size
    end

    # aligns block elements vertically by adding spaces;
    # all lines in block gets changed to have the same # of chars
    # @param type {Symbol} :left (default), :center, :right
    # @param width {Integer} target block width, defaults to the current width
    def v_align! type = nil, width: nil
      line_transformer = case type
                         when :center
                           ->(line, num_spaces) { ' ' * (num_spaces / 2) + line.to_s + (' ' * (num_spaces / 2)) + (num_spaces.odd? ? ' ' : '') }
                         when :right
                           ->(line, num_spaces) { (' ' * num_spaces) + line.to_s }
                         else # :left
                           ->(line, num_spaces) { line.to_s + (' ' * num_spaces) }
                         end

      @width = width unless width.nil? || @width > width
      @array.collect! { |line| line_transformer.call line, @width - line.size }
      self
    end

    # adds a square box around the block;
    # auto-aligns the block, so use {#v_align!}
    # if you want custom alignment for the block
    def box! corners: :round
      corners = Assets::CORNERS[corners]
      v_align!
      @array.collect! { |line| "│#{line}│" }
      @array.unshift "#{corners[0]}#{'─' * width}#{corners[1]}"
      @array << "#{corners[2]}#{'─' * width}#{corners[3]}"
      @width += 2
      self
    end

    # fit the current block to a rectangle by
    # cropping the block and adding a special markers to content;
    # actual content width and height will be 1 char less to store cropping symbols;
    # filling does not align content, {v_align!} does
    # @param width width to fit, nil means don't touch width
    # @param height height to fit, nil means don't touch height
    # @param fill whether to fill column for the sizes provided
    def fit! width: nil, height: nil, fill: false
      # pre-calc width to use below
      @width = width unless width.nil? || (@width < width && !fill)

      unless height.nil?
        if @array.size > height
          @array.slice!((height - 1)..)
          @array << ('░' * @width)
        elsif fill && @array.size < height
          @array += Array.new(height - @array.size, ' ' * @width)
        end
      end
      unless width.nil?
        @array.collect! { |line|
          if line.size > width
            "#{line[...(width - 1)]}░"
          elsif fill && line.size < width
            line << ' ' * (width - line.size)
          else
            line
          end
        }
      end
      self
    end
  end
end
