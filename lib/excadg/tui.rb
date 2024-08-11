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
    DEFAULT_BOX_SIZE = { height: 70, width: 200 }.freeze

    @started_at = DateTime.now.strftime('%Q').to_i

    class << self
      # spawns a thread to show stats to console in background
      def run
        Log.info 'spawning tui'
        Thread.report_on_exception = false
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
        [timed_out ? 'execution timed out' : '🮱  execution completed',
         "#{has_failed ? '🯀  some' : '🮱  no'} vertices failed"]
      end

      # make summary paragraph on veritces
      def stats summary: nil
        Block.column(
          Block.row(
            Block.column(summary || '🮚  running').h_pad!(1).v_align!(:center).box!.h_pad!,
            Block.column(
              *[
                "🮚  time spent (ms): #{DateTime.now.strftime('%Q').to_i - @started_at}",
                "#  vertices seen: #{Broker.instance.vtracker.graph.vertices.size}",
                '🮶  progress:'
              ] + state_stats,
              align: :left
            ).h_pad!(2)
          ),
          Block.row('🮲 🮳  pending vertices and their dependencies:').pad!,
          Block.row(*pending_vertices || 'tracking is n/a', align: :top).h_pad!,
          align: :left
        ).fit!(width: @content_size[:width], height: @content_size[:height], fill: true)
             .box!(corners: :sharp)
      end

      def clear
        print "\e[2J\e[f"
      end

      def refresh_sizes
        @content_size = {
          height: (IO.console&.winsize&.first.nil? || DEFAULT_BOX_SIZE[:height] < IO.console.winsize.first ? DEFAULT_BOX_SIZE[:height] : IO.console.winsize.first) - 4,
          width: (IO.console&.winsize&.last.nil? || DEFAULT_BOX_SIZE[:width] < IO.console&.winsize&.last ? DEFAULT_BOX_SIZE[:width] : IO.console.winsize.last) - 2
        }
      end

      # make states summary, one for a line with consistent placing
      def state_stats
        skeleton = StateMachine::GRAPH.vertices.collect { |v| [v, []] }.to_h
        filled = skeleton.merge(Broker.instance.vtracker.by_state.transform_values { |vertices| vertices.collect(&:name).join(', ') })
        filled.collect { |k, v| format '  %-10s: %s', k, "#{v.empty? ? '<none>' : v}" }
      end

      # gather pending vertices (in :new state) from the tracker
      # and render dependencies they're waiting for
      def pending_vertices
        return nil if Broker.instance.vtracker.nil?
        if Broker.instance.vtracker.by_state[:new].nil? || Broker.instance.vtracker.by_state[:new].empty?
          return Block.column('... no pending vertices').h_pad!
        end

        Broker.instance.vtracker.by_state[:new].sort_by(&:name).collect { |v|
          deps = Broker.instance.vtracker.get_deps v
          deps = nil if deps.empty?
          deps&.sort_by!(&:state)
          width = 20
          Block.column(
            Block.column(v).fit!(width: width - 4).h_pad!.box!,
            '🮦',
            Block.column(*deps || 'no deps to wait').fit!(width: width - 4).h_pad!.box!
          ).fit!(width: width, fill: true).h_pad!(2)
        }
      end
    end
  end
end
