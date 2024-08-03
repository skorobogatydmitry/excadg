# frozen_string_literal: true

require_relative 'assertions'
require_relative 'payload'
require_relative 'vstate_data'

module ExcADG
  # base class for messages between Ractors
  class Request
    attr_reader :self

    def initialize
      @self = Ractor.current
    end

    def to_s
      "#{self.class} from #{@self}"
    end

    # request to get state data
    class GetStateData < ExcADG::Request
      attr_reader :deps

      # @param deps {Array} of VStateData::Key
      def initialize deps: nil
        super()
        @deps = deps
      end

      def filter?
        !@deps.nil?
      end
    end

    # request to update self state in the central storage
    class Update < ExcADG::Request
      attr_reader :data

      def initialize data:
        super()
        Assertions.is_a? data, VStateData::Full

        @data = data
      end
    end

    # request to make and start a new vertex
    class AddVertex < ExcADG::Request
      attr_reader :payload

      def initialize payload:
        super()
        raise "Incorrent payload type: #{payload.class}" unless payload.is_a? Payload

        @payload = payload
      end
    end
  end
end
