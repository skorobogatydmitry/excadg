# frozen_string_literal: true

require 'rgl/adjacency'
require 'rgl/base'

require_relative 'broker'
require_relative 'log'
require_relative 'request'
require_relative 'vstate_data'

module ExcADG
  # carry states and transitions for individual vertices
  class StateMachine
    # sets in stone possible state transitions
    GRAPH = RGL::DirectedAdjacencyGraph.new
    GRAPH.add_edge :new, :ready
    GRAPH.add_edge :ready, :done
    # any transition could end-up in a failed state
    GRAPH.add_vertex :failed
    Ractor.make_shareable GRAPH

    # add states graph to the current object
    def initialize name:
      @state = :new
      @state_edge_bindings = {}
      @state_transition_data = {}

      @name = name
    end

    # bind action to one of the state graph's edges
    def bind_action source, target, &block
      [source, target].each { |state|
        raise WrongState, "unknown state #{state}" unless GRAPH.has_vertex? state
      }
      raise WrongTransition.new source, target unless GRAPH.has_edge? source, target

      edge = GRAPH.edges.find { |e| e.source == source && e.target = target }
      @state_edge_bindings[edge] = block
    end

    # transition to next state
    # @return: state data (result) / nil if it's a final step
    def step
      Log.debug 'taking another step'
      assert_state_transition_bounds

      target_candidates = GRAPH.each_adjacent @state
      Log.debug "possible candidates: #{target_candidates.size}"
      return nil if target_candidates.none?
      raise WrongState, "state #{@state} has more than one adjacent states" unless target_candidates.one?

      target = target_candidates.first
      Log.debug "found a candidate: #{target}"
      edge = GRAPH.edges.find { |e| e.source == @state && e.target = target }
      begin
        @state_transition_data[target] = @state_edge_bindings[edge].call
        @state = target
        Log.debug "moved to #{@state}"
      rescue StandardError => e
        Log.error "step failed with #{e} / #{e.backtrace}"
        @state_transition_data[:failed] = e
        @state = :failed
      ensure
        begin
          Broker.ask Request::Update.new data: state_data
        rescue StandardError => e
          @state_transition_data[:failed] = e
          @state = :failed
          Broker.ask Request::Update.new data: state_data
        end
      end
      @state_transition_data[@state]
    end

    def assert_state_transition_bounds
      raise NotAllTransitionsBound, GRAPH.edges - @state_edge_bindings.keys unless GRAPH.edges.eql? @state_edge_bindings.keys
    end

    # makes state data for the current vertex
    def state_data
      VStateData::Full.new name: @name, data: @state_transition_data[@state], state: @state
    end

    class WrongState < StandardError; end

    class WrongTransition < StandardError
      def initialize src, dest
        super("Transition #{src} -> #{dest} is not available.")
      end
    end

    class NotAllTransitionsBound < StandardError; end
  end
end
