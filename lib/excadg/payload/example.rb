# frozen_string_literal: true

require 'benchmark'

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

    # payload that occupies a CPU core for several seconds,
    # is suitable for perfomance tests
    class Benchmark
      include Payload
      def get
        lambda {
          Log.info(::Benchmark.measure {
            10_000.downto(1) { |i| 10_000.downto(1) { |j| i * j } }
          })
        }
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
