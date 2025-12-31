require 'tui'
require 'date'
require 'io/console'

require_relative 'broker'
require_relative 'state_machine'


module ExcADG
  # render status on the screen
  module AdgTui
    MAX_VERTEX_TO_SHOW = 10

    class << self

      def run
        Log.info 'spawning tui'
        @started_at = DateTime.now.strftime('%Q').to_i
        @thread = Tui::run Tui::Layout::new { stats }
      end

      def summarize has_failed, timed_out
        @thread.kill
        print stats summary: get_summary(has_failed, timed_out)
      end

      def get_summary has_failed, timed_out
        [timed_out ? 'execution timed out' : '🮱  execution completed',
         "#{has_failed ? '🯀  some' : '🮱  no'} vertices failed"]
      end

      private

      # make summary paragraph on veritces
      def stats summary: nil
        Tui::Block.column(
          Tui::Block.row(
            Tui::Block.column(summary || '🮚  running').h_pad!(1).v_align!(:center).box!.h_pad!,
            Tui::Block.column(
              *[
                "🮚  time spent (ms): #{DateTime.now.strftime('%Q').to_i - @started_at}",
                "#  vertices seen: #{Broker.instance.vtracker.graph.vertices.size}",
                '🮶  progress:'
              ] + state_stats,
              align: :left
            ).h_pad!(2)
          ),
          Tui::Block.row('🮲 🮳  pending vertices and their dependencies:').pad!,
          Tui::Block.row(*pending_vertices || 'tracking is n/a', align: :top).h_pad!,
          align: :left
        )
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
          return Tui::Block.column('... no pending vertices').h_pad!
        end

        Broker.instance.vtracker.by_state[:new].sort_by(&:name).collect { |v|
          deps = Broker.instance.vtracker.get_deps v
          deps = nil if deps.empty?
          deps&.sort_by!(&:state)
          width = 20
          Tui::Block.column(
            Tui::Block.column(v).fit!(width: width - 4).h_pad!.box!,
            '🮦',
            Tui::Block.column(*deps || 'no deps to wait').fit!(width: width - 4).h_pad!.box!
          ).fit!(width: width, fill: true).h_pad!(2)
        }
      end
    end
  end
end
