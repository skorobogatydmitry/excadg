# frozen_string_literal: true

require 'rgl/adjacency'

module ExcADG
  # tracker for {Vertex}-es graph:
  # it's hooked by {Broker} to register dependencies polling events
  # and make an actual graph of vertices with states in runtime
  #
  # it's not possible to do this in other way, because vertices can be spawned:
  # - in any order => code is not guaranteed to know the full graph (even static one)
  # - dynamically => there is no central place but {Broker} that's aware of all vertices
  class VTracker
    attr_reader :graph, :by_state

    def initialize
      @graph = RGL::DirectedAdjacencyGraph.new
      @by_state = {}
    end

    # register the vertex and its new known deps in the @graph and by_state cache
    # @param vertice vertice that requested info about deps
    # @param deps list of dependencies as supplied by {Request::GetStateData}
    def track vertex, deps = []
      Assertions.is_a? vertex, Vertex
      Assertions.is_a? deps, Array

      @graph.add_vertex vertex
      add_to_states_cache vertex, vertex.state

      deps.each { |raw_dep|
        # it could be not a Vertex, so do a lookup through data store
        next unless Broker.data_store[raw_dep]

        dep_data = Broker.data_store[raw_dep]
        add_to_states_cache dep_data.vertex, dep_data.state
        @graph.add_edge vertex, dep_data.vertex
      }
    end

    # get all vertex's dependencies
    # @param vertex {Vertex} vertex to lookup known dependencies for
    def get_deps vertex
      @graph.adjacent_vertices vertex
    end

    private

    # adds a given {Vertex} in state to @by_state cache;
    # makes sure to remove it from the rest of the lists;
    # lazily initializes the cache
    def add_to_states_cache vertex, state
      # TODO: shouldn't we add these vertices to the graph as "unresolved" up until they appear as {Vertex}
      return unless state

      @by_state.each_value { |v| v.delete vertex }
      @by_state[state] ||= []
      @by_state[state] << vertex
    end
  end
end
