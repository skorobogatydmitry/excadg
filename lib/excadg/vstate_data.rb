# frozen_string_literal:true

require 'json'

require_relative 'assertions'
require_relative 'state_machine'
require_relative 'vertex'

module ExcADG
  # Vertex state data as filled by {ExcADG::StateMachine}
  # to be transferred between vertices
  module VStateData
    # class to support comparison and Arrays operations
    class Key
      attr_reader :name, :vertex

      def initialize name: nil, vertex: nil
        raise 'name or vertex are required' if name.nil? && vertex.nil?

        Assertions.is_a?(vertex, Vertex) unless vertex.nil?

        @name = name
        @vertex = vertex
      end

      include Comparable
      def <=> other
        return nil unless (other.is_a? self.class) || (is_a? other.class)
        # no mutual fields to compare
        return nil if (@vertex.nil? && other.name.nil?) || (@name.nil? && other.vertex.nil?)

        # name takes preference
        @name.nil? || other.name.nil? ? @vertex <=> other.vertex : @name <=> other.name
      end

      def eql? other
        (self <=> other)&.zero? || false
      end

      def to_s
        (@name || @vertex).to_s
      end
    end

    # contains actual data
    class Full < Key
      attr_reader :state, :data, :name, :vertex

      # param state: Symbol, one of StateMachine.GRAPH.vertices
      # param data: all data returned by a Vertice's Payload
      # param name: Symboli -c name of the associated Vertex
      # param vertex: Vertex that produced the data
      def initialize state:, data:, name:, vertex: nil
        # observation: Ractor.current returns Vertex object if invoked from a Vertex
        super(name:, vertex: vertex || Ractor.current)
        @state = state
        @data = data
      end

      def to_s
        "#{name || vertex} (#{state})"
      end

      # method omits objects without a good known text representation
      def to_json(*args)
        {
          name: @name,
          state: @state,
          data: @data
        }.to_json(*args)
      end

      # converts full object to key to use in Hash
      def to_key
        Key.new vertex: @vertex, name: @name
      end

      # auto-generated methods to check states easier;
      # note: define_method causes these object to become un-shareable
      # what breaks Broker's messaging
      def method_missing(method, *_args, &_block)
        raise NoMethodError unless respond_to_missing? method, _args

        @state.eql? method[...-1].to_sym
      end

      def respond_to_missing? method, *_args
        method.to_s.end_with?('?') && ExcADG::StateMachine::GRAPH.has_vertex?(method[...-1].to_sym)
      end
    end
  end
end
