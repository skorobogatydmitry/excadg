require 'date'
require 'io/console'

require_relative 'broker'
require_relative 'state_machine'

require_relative 'tui/assets'
require_relative 'tui/block'
require_relative 'tui/format'

module ExcADG
  # render status on the screen
  module Tui
    MAX_VERTEX_TO_SHOW = 10
    DELAY = 0.2
    DEFAULT_BOX_SIZE = { height: 50, width: 150 }.freeze

    @started_at = DateTime.now.strftime('%Q').to_i

    class << self
      # spawns a thread to show stats to console in background
      def run
        Log.info 'spawning tui'
        @thread = Thread.new {
          loop {
            # print_in_box stats
            clear
            refresh_sizes
            print stats
            sleep DELAY
          }
        }
      end

      def summarize has_failed, timed_out
        @thread.kill
        clear
        print stats summary: get_summary(has_failed, timed_out)
      end

      # private

      def get_summary has_failed, timed_out
        [timed_out ? 'execution timed out' : 'execution completed',
         "#{has_failed ? 'some' : 'no'} vertices failed"]
      end

      # make summary paragraph on veritces
      def stats summary: nil
        Block.column(
          Block.column(summary || 'running').h_pad!(1).box!.v_align!(:center, width: @content_size[:width]),
          Block.column(
            *[
              "time spent (ms): #{DateTime.now.strftime('%Q').to_i - @started_at}",
              "vertices seen: #{Broker.data_store.size}",
              'progress:'
            ] + state_stats,
            align: :left
          ).h_pad!(2),
          align: :left
        ).fit!(width: @content_size[:width], height: @content_size[:height], fill: true)
             .box!(corners: :sharp)
      end

      def clear
        print "\e[2J\e[f"
      end

      def refresh_sizes
        box_size = {
          height: IO.console&.winsize&.first.nil? || DEFAULT_BOX_SIZE[:height] < IO.console.winsize.first ? DEFAULT_BOX_SIZE[:height] : IO.console.winsize.first,
          width: IO.console&.winsize&.last.nil? || DEFAULT_BOX_SIZE[:width] < IO.console&.winsize&.last ? DEFAULT_BOX_SIZE[:width] : IO.console.winsize.last
        }.freeze
        @content_size = {
          height: box_size[:height] - 4, # 2 for borders, 1 for \n, 1 for remark
          width: box_size[:width] - 5 # 2 for borders, 2 to indent
        }.freeze
        @line_template = "│ %-#{@content_size[:width]}s │\n"
      end

      # make states summary, one for a line with consistent placing
      def state_stats
        skeleton = StateMachine::GRAPH.vertices.collect { |v| [v, []] }.to_h
        # rubocop:disable Style/HashTransformValues
        filled = skeleton.merge Broker.data_store.to_a
                                      .group_by(&:state)
                                      .collect { |state, vertices| [state, vertices_stats(vertices)] }
                                      .to_h
        # rubocop:enable Style/HashTransformValues
        filled.collect { |k, v| format '  %-10s: %s', k, "#{v.empty? ? '<none>' : v}" }
      end

      def vertices_stats vertice_pairs
        vertice_pairs.collect(&:name).join(', ')
      end
    end
  end
end
