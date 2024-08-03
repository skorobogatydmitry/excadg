require 'timeout'

module ExcADG::Tui
  describe Block do
    subject(:block) { Block.new ['first row', 'second row', 'third row', ''] }

    it 'has base attributes' do
      expect(block.width).to eq 10
      expect(block.height).to eq 4
      expect(block.to_s).to eq block.array.join("\n")
    end
    it 'casts argument to string by default' do
      b = Block.new :some
      expect(b.array.first).to eq :some.to_s
    end
    it 'appends lines' do
      newb = block << '1' * 12
      expect(newb).to eq block
      expect(block.array.last).to eq '1' * 12
      expect(block.height).to eq 5
      expect(block.width).to eq 12

      block << %w[1 2 3]
      expect(block.array.last).to eq '3'
      expect(block.height).to eq 8
      expect(block.width).to eq 12
    end
    it 'prepends lines' do
      newb = block >> '1' * 12
      expect(newb).to eq block
      expect(block.array.first).to eq '1' * 12
      expect(block.height).to eq 5
      expect(block.width).to eq 12

      block >> %w[1 2 3]
      expect(block.array.first).to eq '1'
      expect(block.height).to eq 8
      expect(block.width).to eq 12
    end
    it 'collects with mutation' do
      block.collect! { |line|
        "#{line}test"
      }
      block.array.each { |el|
        expect(el).to end_with 'test'
      }
      expect(block.width).to eq 14
    end

    context 'construction tests' do
      subject(:raw_column) { ['first row', 'second row', 'third row', ''] }

      it 'makes a column from raw data' do
        block = Block.column(*raw_column)
        expect(block).to be_a Block
        expect(block.width).to eq raw_column.collect(&:size).max
        expect(block.height).to eq raw_column.size
      end

      it 'makes a row from raw data' do
        block = Block.row(*raw_column)
        expect(block).to be_a Block
        expect(block.width).to eq raw_column.collect(&:size).sum
        expect(block.height).to eq 1
      end

      it 'allows to patch rows in column' do
        block = Block.column(*raw_column) { |row|
          expect(row).to be_a Block
          row.box!
        }
        expect(block).to be_a Block
        expect(block.width).to eq raw_column.collect(&:size).max + 2
        expect(block.height).to eq raw_column.size + 2 * raw_column.size # each element is 2 lines higher
      end

      it 'allows to patch columns in a row' do
        block = Block.row(*raw_column) { |col|
          expect(col).to be_a Block
          col.box!
        }
        expect(block).to be_a Block
        expect(block.width).to eq raw_column.collect(&:size).sum + raw_column.size * 2
        expect(block.height).to eq 3
      end

      it 'allows nesting rows to columns' do
        block = Block.column(
          Block.row(*raw_column),
          Block.row(*raw_column)
        )

        expect(block.width).to eq raw_column.collect(&:size).sum
        expect(block.height).to eq 2
      end

      it 'allows nesting columns to rows' do
        block = Block.row(
          Block.column(*raw_column),
          Block.column(*raw_column)
        )

        expect(block.width).to eq raw_column.collect(&:size).max * 2
        expect(block.height).to eq raw_column.size
      end

      it 'aligns columns by default' do
        block = Block.column(*raw_column)
        block.array.each { |line|
          expect(line.size).to eq block.width
        }
        block = Block.row(raw_column, ['some'], align: :top)
        block.array.each_with_index { |line, idx|
          expect(line.size).to eq raw_column.collect(&:size).max + 4
          expect(line).to end_with(idx.zero? ? 'some' : '    ')
        }
        expect(block.height).to eq raw_column.size
      end
      # TODO: add tests for aligning
    end

    context 'padding tests' do
      it 'adds vertical padding' do
        new_col = block.v_pad!(2) { block }
        expect(new_col).to eq block
        expect(block.height).to eq 8
        expect(block.array.first).to eq ' ' * 10
        expect(block.width).to eq 10
        expect(block).to be_a Block
        block.array.each { |row|
          expect(row).to be_a String
        }
      end
      it 'adds horisontal paddings' do
        original_widths = block.array.collect(&:size)
        new_blk = block.h_pad!(2) { column }
        expect(new_blk).to eq block
        original_widths.each_with_index { |e, i|
          expect(block.array[i].size).to eq e + 4
        }
        expect(block.height).to eq 4
      end
      it 'adds both paddings' do
        original_widths = block.array.collect(&:size)
        original_width = block.width
        original_height = block.height

        block.pad!(3) { block }
        expect(block.height).to eq original_height + 6
        expect(block.width).to eq original_width + 6
        original_widths.each_with_index { |e, idx|
          expect(block.array[idx + 3].size).to eq e + 6
        }
      end
    end
    context 'aligning tests' do
      it 'aligns to left by default' do
        original_array = block.array.clone
        original_width = block.width
        same_block = block.v_align!

        expect(same_block).to eq block
        expect(block.width).to eq original_width
        block.array.each_with_index { |line, idx|
          expect(line.size).to eq block.width
          expect(line).to start_with original_array[idx]
        }
      end
      it 'aligns to right' do
        original_array = block.array.clone
        original_width = block.width
        same_block = block.v_align!(:right)

        expect(same_block).to eq block
        expect(block.width).to eq original_width
        block.array.each_with_index { |line, idx|
          expect(line.size).to eq block.width
          expect(line).to end_with original_array[idx]
        }
      end
      it 'aligns to center' do
        original_array = block.array.clone
        original_width = block.width
        same_block = block.v_align!(:center)

        expect(same_block).to eq block
        expect(block.width).to eq original_width
        block.array.each_with_index { |line, idx|
          expect(line.size).to eq block.width
          expect(line).to include original_array[idx]
        }
      end
      it 'extends to width specified' do
        original_array = block.array.clone
        original_width = block.width
        same_block = block.v_align! width: block.width + 5

        expect(same_block).to eq block
        expect(block.width).to eq original_width + 5
        block.array.each_with_index { |line, idx|
          expect(line.size).to eq block.width
          expect(line).to start_with original_array[idx]
        }
      end
      it 'does not crop block' do
        original_array = block.array.clone
        original_width = block.width
        same_block = block.v_align! width: block.width - 5

        expect(same_block).to eq block
        expect(block.width).to eq original_width
        block.array.each_with_index { |line, idx|
          expect(line.size).to eq block.width
          expect(line).to start_with original_array[idx]
        }
      end
    end
    context 'boxing tests' do
      it 'adds 1 space around' do
        original_width = block.width
        original_height = block.height
        boxed = block.box!
        expect(boxed).to eq block
        expect(original_height + 2).to eq block.height
        original_height.times { |idx|
          expect(block.array[1 + idx].size).to eq original_width + 2
        }
      end

      it 'crops block if it does not fit' do
        original_width = block.width
        original_height = block.height

        block.fit! width: original_width - 3, height: original_height - 2

        expect(block.width).to eq original_width - 3
        expect(block.height).to eq original_height - 2
        expect(block.width).to eq block.array.collect(&:size).max

        expect(block.array.last[-1]).to eq '░'
        expect(block.array.first[-1]).to eq '░'
      end
      it 'does not touch content if it fits' do
        original_width = block.width
        original_height = block.height

        block.fit! width: original_width + 1, height: original_height + 1

        expect(block.width).to eq original_width
        expect(block.height).to eq original_height
        expect(block.width).to eq block.array.collect(&:size).max
      end
      it 'crops only width' do
        original_width = block.width
        original_height = block.height
        last_line = block.array.last

        block.fit! width: original_width - 3

        expect(block.width).to eq original_width - 3
        expect(block.height).to eq original_height
        expect(block.width).to eq block.array.collect(&:size).max

        expect(block.array.last).to eq last_line
        expect(block.array.first[-1]).to eq '░'
      end
      it 'crops only height' do
        original_width = block.width
        original_height = block.height
        first_line = block.array.first

        block.fit! height: original_height - 2

        expect(block.width).to eq original_width
        expect(block.height).to eq original_height - 2
        expect(block.width).to eq block.array.collect(&:size).max

        expect(block.array.last[-1]).to eq '░'
        expect(block.array.first).to eq first_line
      end
      it 'fills if asked to' do
        original_width = block.width
        original_height = block.height

        block.fit! width: original_width + 1, height: original_height + 1, fill: true

        expect(block.width).to eq original_width + 1
        expect(block.height).to eq original_height + 1
        expect(block.width).to eq block.array.collect(&:size).max

        block.array.each { |line|
          expect(line).to end_with ' '
        }
        expect(block.array.last.delete(' ')).to be_empty
      end
    end
  end
end
