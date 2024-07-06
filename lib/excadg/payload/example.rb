# frozen_string_literal: true

require_relative '../broker'
require_relative '../request'

module ExcADG
  # payload examples to demonstrate framework capabilities
  # most of the payloads in the file are used in tests
  module Payload::Example
    # minimalistic payload that does nothing
    # but echoes its args or :ping by default
    class Echo
      include Payload
      def get
        -> { @args }
      end

      def sanitize args
        args.nil? ? :ping : args
      end
    end

    # dependencies data processing example
    # deps_data is an Array with a VStateData objects for each dependency
    # the example just checks that all deps returned :ping, fails otherwise
    class Receiver
      include Payload
      def get
        lambda { |deps_data|
          deps_data.collect { |d|
            raise 'incorrect data received from dependencies' unless d.data.eql? :ping
          }
        }
      end
    end

    # payload that fails
    class Faulty
      include Payload

      def get
        -> { raise @args }
      end
    end

    # payload that sleeps @args or 1 second(s)
    class Sleepy
      include Payload
      def get
        -> { sleep @args }
      end

      def sanitize args
        args.is_a?(Integer) ? args : 0.1
      end
    end

    # calculate Nth member of the function
    # y = x(n) * (x(n-1)) where x(0) = 0 and x(1) = 1
    # it illustrates how payload can be customized with @args
    # and extended by adding methods
    class Multiplier
      include Payload
      def get
        -> { get_el x: @args }
      end

      def get_el x:
        case x
        when 0 then 0
        when 1 then 1
        else
          x * get_el(x: x - 1)
        end
      end
    end

    # payload that does something on condition received from its deps
    # see spec/vertex_spec.rb for full example
    class Condition
      include Payload
      def get
        lambda { |deps_data|
          ExcADG::Broker.ask ExcADG::Request::AddVertex.new(payload: Echo.new) if deps_data.all? { |d| d.data.eql? :trigger }
        }
      end
    end

    # payload that implements an idiomatic loop by
    # making N vertices - one for each of its dependencies
    class Loop
      include Payload
      def get
        lambda { |deps_data|
          deps_data.first.data.collect { |e|
            ExcADG::Broker.ask ExcADG::Request::AddVertex.new payload: Echo.new(args: e)
          }
        }
      end
    end
  end
end
