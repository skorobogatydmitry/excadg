# frozen_string_literal: true

require_relative 'format'

module ExcADG::Tui
  # basic TUI building block;
  # in a nutshell, it's a column, as {String}s in it are printed vertically one by one (see {#to_s});
  # it could be a row only semantically if it's a part of a vertically composed array (see {.column})
  class Block
    attr_reader :width, :array

    include Format

    # transform array or "rows" to a single column;
    # @example
    #   Block.column "some", "other"               # some and other will be centered in column by default
    #   Block.column "some", "other", align: :left # some and other will be shifted to the left
    #   Block.column
    #     Block.row("one", "two"),
    #     "three"
    #   ]} # one and two will be printed in the first row, three will be below them centered
    #   Block.column("some", "other") { |el| el.box! } # enclose both string to boxes before making a row
    # @param *rows array of rows ({Block}s / {String}s)
    # @param align how to align blocks between each other: :center (default), :right, :left
    # @param &block idividual row processor, the block is supplied with {Block}s
    def self.column *rows, align: nil, &block
      # row could be a String, make an array of horizontal lines from it
      rows.collect! { |col| col.is_a?(Block) ? col : Block.new(col) }
      rows.collect!(&block) if block_given? # allow to pre-process "rows"
      max_row_width = rows.collect(&:width).max
      Block.new rows.collect! { |blk|
        extra_columns = max_row_width - blk.width
        case align
        when :left then blk.collect! { |line| line + ' ' * extra_columns }
        when :right then blk.collect! { |line| ' ' * extra_columns + line }
        else
          blk.h_pad!(extra_columns / 2)
          extra_columns.odd? ? blk.collect! { |line| line + ' ' } : blk
        end
        blk.array # get the array to join using builtin flatten
      }.flatten!
    end

    # squash a row of columns (blocks) to a single block
    # @example
    #   Block.row "some", "other" # => "someother"
    #   Block.row "some", ["other", "foo"], aligh: bottom # some will be shifted down by 1 line
    #   Block.row("some", "other") { |blk| blk.box! } # both columns will be enclosed in a box
    # @param *cols array of columns ({Block}s / {String}s)
    # @param align how to align blocks between each other: :center (default), :top, :bottom
    # @param &block idividual column processor, the block is supplied with {Block}s
    def self.row *cols, align: nil, &block
      cols.collect! { |col| col.is_a?(Block) ? col : Block.new(col) }
      cols.collect!(&block) if block_given? # allow to pre-process columns
      max_col_height = cols.collect(&:height).max
      Block.new cols.collect! { |col|
        extra_lines = max_col_height - col.height
        case align
        when :top then col << Array.new(extra_lines, '')
        when :bottom then col >> Array.new(extra_lines, '')
        else
          col.v_pad!(extra_lines / 2)
          col << '' if extra_lines.odd?
        end
        col.v_align! # is needed due to transpose call below
        col.array # get the array to process using builtin methods
      }.transpose.collect(&:join)
    end

    # make printable
    def to_s
      @array.join "\n"
    end

    # add extra lines from the supplied array to the block;
    # no auto-alignment is performed, see {#v_align} to make width even
    # @param other either {Array} or {String} to push back
    def << other
      other.is_a?(Array) ? @array += other : @array << other
      @width = @array.collect(&:size).max
      self
    end

    # add extra lines to the start of the block
    # @param other either {Array} or {String} to push forward
    # @example
    #   Block.column '1'
    #   block << %w[2 3] # now block has %w[2 3 1]
    def >> other
      case other
      when Array
        other.reverse_each { |i|
          @array.unshift i
        }
      when String
        @array.unshift other
      end
      @width = @array.collect(&:size).max
      self
    end

    # column's height is its size
    def height
      @array.size
    end

    # main inline modification method
    def collect! &block
      @array.collect!(&block)
      @width = @array.collect(&:size).max
    end

    private

    # constructor is private;
    # {#column} and {#row} are enough to make blocks;
    # in case you need to align a single block, use e.g. `Block.column("one", "two") { |blk| blk.box!.pad! 2 }`
    def initialize arg
      case arg
      when Array then @array = arg
      when String then @array = [arg]
      else raise "can't make block from #{arg.class}"
      end
      @width = @array.collect(&:size).max
    end
  end
end
