# frozen_string_literal: true

require_relative 'assertions'
require_relative 'vstate_data'

module ExcADG
  # collection of {ExcADG::VStateData} for {ExcADG::Broker}
  class DataStore
    def initialize
      # two hashes to store VStateData and access them fast by either key
      @by_name = {}
      @by_vertex = {}
      @size = 0
    end

    # add new element to the store
    # adds it to the two hashes to access lated by either attribute
    # @return current number of elements
    def << new
      Assertions.is_a? new, VStateData::Full
      if (by_name = @by_name[new.name]) && !(by_name.vertex.eql? new.vertex)
        raise DataSkew,
              "Vertex named #{new.name} - #{new.vertex} is recorded as #{by_name.vertex} in state"
      end
      if (by_vertex = @by_vertex[new.vertex]) && !(by_vertex.name.eql? new.name)
        raise DataSkew,
              "Vertex #{new.vertex} named #{new.name} is already named #{by_vertex.name}"
      end

      @size += 1 unless key? new

      @by_name[new.name] = new if new.name
      @by_vertex[new.vertex] = new if new.vertex
    end

    # retrieves {VStateData} by key
    # @param key {Vertex} or {VStateData::Key} or vertex name (String || Symbol) to retrieve Full state data
    # @return VStateData::Full for the respective key
    # @raise StandardError if key is not of a supported type
    def [] key
      Assertions.is_a? key, [Vertex, VStateData::Key, Symbol, String]

      case key
      when Vertex then @by_vertex[key]
      when Symbol, String then @by_name[key]
      when VStateData::Key
        if key.name && @by_name.key?(key.name)
          @by_name[key.name]
        elsif key.vertex && @by_vertex.key?(key.vertex)
          @by_vertex[key.vertex]
        else
          nil
        end
      end
    end

    # retrieve all vertices state data,
    # could contain huge amount of data and be slow to work with;
    # prefer to access vertices data by name using [] instead
    def to_a
      (@by_name.values + @by_vertex.values).uniq
    end

    # checks if there is data for a given key
    def key? key
      case key
      when Vertex then @by_vertex.key? key
      when Symbol, String then @by_name.key? key
      when VStateData::Key
        @by_name.key?(key.name) || @by_vertex.key?(key.vertex)
      else
        false
      end
    end

    def empty?
      @size.zero?
    end

    class DataSkew < StandardError; end
  end
end
