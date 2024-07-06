# frozen_string_literal:true

require_relative 'assertions'
require_relative 'log'
require_relative 'vstate_data'

module ExcADG
  # manage list of dependencies
  # dependencies could be of 2 types:
  # - vertex - see vertex.rb
  # - symbol - :name attribute of the vertex
  class DependencyManager
    attr_reader :deps, :data

    # @param deps list of symbols or vertices to watch for as dependencies
    def initialize deps:
      Assertions.is_a? deps, Array
      Assertions.is_a? deps, [Vertex, Symbol]

      @deps = deps.collect { |raw_dep|
        case raw_dep
        when Symbol then VStateData::Key.new name: raw_dep
        when Vertex then VStateData::Key.new vertex: raw_dep
        end
      }
      @data = []
    end

    # deduct (update) dependencies with new data
    # - counts :done dependencies
    # - preserves :done deps data
    # @param new_data - Array of VStateData retrieved from the broker
    def deduct_deps new_data
      data = filter_foreign new_data
      Log.debug "received deps: #{data}"

      assert_failed data

      done_deps = data.select(&:done?)
      @data += done_deps
      Log.debug "done deps: #{done_deps}"

      @deps.reject! { |dep| done_deps.include? dep }
      Log.info "deps left: #{@deps.collect(&:to_s)}}"
    end

    private

    # filters out deps doesn't belong to the manager
    def filter_foreign new_data
      if (new_data - @deps).empty?
        new_data
      else
        Log.warn 'non-deps state received, filtering'
        Log.debug "non-dep states: #{new_data - @deps}"
        new_data.filter { |state_data| deps.include? state_data }
      end
    end

    # checks if any dependencies in the received data are failed
    def assert_failed data
      failed_deps = data.select(&:failed?).collect(&:to_s)
      Log.debug "failed deps: #{failed_deps}"
      raise "some deps failed: #{failed_deps}" unless failed_deps.empty?
    end
  end
end
