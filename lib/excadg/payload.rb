# frozen_string_literal: true

module ExcADG
  # module to base payload for {ExcADG::Vertex} -es on it,
  # reason for having this special module to provider simple labmdas
  # is that Ractor (which is a base for {ExcADG::Vertex})
  # require its parameters scope to be shareable
  module Payload
    attr_accessor :args

    # main method of the payload that holds code to be executed within vertex,
    # vertex takes care of error processing - there is no need to mask exceptions,
    # this method should return a Proc, that:
    # * could receive up to 1 arguments
    # * 1st argument, if specified, is an {Array} of {ExcADG::VStateData} from the vertex dependencies
    # * could access @args of the obejct, which was set on object's constructing
    # @return {Proc}
    # @raise {ExcADG::Payload::NoPayloadSet} by default to fail vertices with partially-implemented payload
    def get
      raise NoPayloadSet, 'payload is empty'
    end

    # constructor to store arguments for the lambda in the object
    #
    # implementation implies that child class could implement {#sanitize}
    # to transform args as needed
    def initialize args: nil
      @args = respond_to?(:sanitize) ? send(:sanitize, args) : args
    end

    class NoPayloadSet < StandardError; end
    class IncorrectPayloadArity < StandardError; end
  end
end

require_relative 'payload/example'
require_relative 'payload/wrapper'
