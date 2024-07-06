# frozen_string_literal: true

require 'date'
require 'io/console'

require_relative 'broker'
require_relative 'state_machine'

module ExcADG
  # render status on the screen
  module Tui
    MAX_VERTEX_TO_SHOW = 10
    DELAY = 0.2
    DEFAULT_BOX_SIZE = { height: 50, width: 150 }.freeze
    # TODO: do runtime calc
    BOX_SIZE = {
      height: DEFAULT_BOX_SIZE[:height] > (IO.console&.winsize&.first || 1000) ? IO.console.winsize.first : DEFAULT_BOX_SIZE[:height],
      width: DEFAULT_BOX_SIZE[:width] > (IO.console&.winsize&.last || 1000) ? IO.console.winsize.last : DEFAULT_BOX_SIZE[:width]
    }.freeze
    CONTENT_SIZE = {
      height: BOX_SIZE[:height] - 4, # 2 for borders, 1 for \n, 1 for remark
      width: BOX_SIZE[:width] - 5 # 2 for borders, 2 to indent
    }.freeze
    LINE_TEMPLATE = "| %-#{CONTENT_SIZE[:width]}s |\n".freeze

    @started_at = DateTime.now.strftime('%Q').to_i

    class << self
      # spawns a thread to show stats to console in background
      def run
        Log.info 'spawning tui'
        @thread = Thread.new {
          loop {
            print_in_box stats
            sleep DELAY
          }
        }
      end

      def summarize has_failed, timed_out
        @thread.kill
        print_in_box stats + (print_summary has_failed, timed_out)
      end

      private

      # @param content is a list of lines to print
      def print_in_box content
        clear
        print "+-#{'-' * CONTENT_SIZE[:width]}-+\n"
        content[..CONTENT_SIZE[:height]].each { |line|
          if line.size > CONTENT_SIZE[:width]
            printf LINE_TEMPLATE, "#{line[...(CONTENT_SIZE[:width] - 3)]}..."
          else
            printf LINE_TEMPLATE, line
          end
        }
        if content.size < CONTENT_SIZE[:height]
          (CONTENT_SIZE[:height] - content.size).times { printf LINE_TEMPLATE, ' ' }
        else
          printf LINE_TEMPLATE, '<some content did not fit and was cropped>'[..CONTENT_SIZE[:width]]
        end
        print "+-#{'-' * CONTENT_SIZE[:width]}-+\n"
      end

      def print_summary has_failed, timed_out
        [timed_out ? 'execution timed out' : 'execution completed',
         "#{has_failed ? 'some' : 'no'} vertices failed"]
      end

      # make summary paragraph on veritces
      def stats
        [
          "time spent (ms): #{DateTime.now.strftime('%Q').to_i - @started_at}",
          "vertices seen: #{Broker.data_store.size}",
          'progress:'
        ] + state_stats.collect { |line| "  #{line}" }
      end

      def clear
        print "\e[2J\e[f"
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
        filled.collect { |k, v| format '%-10s: %s', k, "#{v.empty? ? '<none>' : v}" }
      end

      def vertices_stats vertice_pairs
        full_list = vertice_pairs.collect(&:name)
        addition = full_list.size > MAX_VERTEX_TO_SHOW ? "... and #{full_list.size - MAX_VERTEX_TO_SHOW} more" : ''
        full_list[0...MAX_VERTEX_TO_SHOW].join(', ') + addition
      end
    end
  end
end
