# frozen_string_literal: true

require_relative 'broker'
require_relative 'dependency_manager'
require_relative 'log'
require_relative 'payload'
require_relative 'request'
require_relative 'rtimeout'
require_relative 'state_machine'
require_relative 'vtimeout'

module ExcADG
  # Individual vertex of the execution graph to run in a separated Ractor
  class Vertex < Ractor
    include RTimeout

    # @return parsed info about the Ractor: number, file, line in file, status
    def info
      inspect.scan(/^#<Ractor:#(\d+)\s(.*):(\d+)\s(\w+)>$/).first
    end

    # Ractor's internal status
    # @return Symbol, :unknown if parsing failed
    def status
      (info&.dig(3) || :unknwon).to_sym
    end

    # @return Ractor's number, -1 if parsing failed
    def number
      info&.dig(0).to_i || -1
    end

    def to_s
      "#{number} #{status}"
    end

    # below are shortcut methods to access Vertex data from the main Ractor

    # obtains current Vertex-es data by lookup in the Broker's data,
    # available from the main Ractor only
    def data
      Broker.data_store[self]
    end

    # gets current Vertex's state,
    # available from the main Ractor only
    def state
      data&.state
    end

    # gets current Vertex's name,
    # available from the main Ractor only
    def name
      data&.name
    end

    class << self
      # make a vertex, it runs automagically
      # @param payload Payload object to run in this Vertex
      # @param name optional vertex name to identify vertex
      # @param deps list of other Vertices or names to wait for
      # @param timeout {ExcADG::VTimeouts} or total time in seconds for the payload to run
      # @raise Payload::IncorrectPayloadArity in case payload returns function with arity > 1
      # @raise Payload::NoPayloadSet in case payload provided has incorrect type
      def new payload:, name: nil, deps: [], timeout: nil
        raise Payload::NoPayloadSet, "expected payload, got #{payload.class}" unless payload.is_a? Payload

        raise Payload::IncorrectPayloadArity, "arity is #{payload.get.arity}, supported only 0 and 1" unless [0, 1].include? payload.get.arity

        dm = DependencyManager.new(deps: deps)
        vtimeout = timeout.is_a?(VTimeout) ? timeout : VTimeout.new(payload: timeout)

        super(payload, name, vtimeout, dm) { |payload, name, vtimeout, deps_manager|
          state_machine = StateMachine.new(name: name || "v#{number}".to_sym)
          state_machine.with_fault_processing {
            await(timeout: vtimeout.global) {
              Broker.ask Request::Update.new data: state_machine.state_data
              Log.info 'building vertex lifecycle'
              state_machine.bind_action(:new, :ready) {
                await(timeout: vtimeout.deps) {
                  until deps_manager.deps.empty?
                    deps_data = Broker.ask Request::GetStateData.new(deps: deps_manager.deps)
                    deps_manager.deduct_deps deps_data
                    sleep 0.2
                  end
                  deps_manager.data
                }
              }
              state_machine.bind_action(:ready, :done) {
                function = payload.get
                await(timeout: vtimeout.payload) {
                  case function.arity
                  when 0 then function.call
                  when 1 then function.call state_machine.state_data.data
                  else
                    raise Payload::IncorrectPayloadArity, "unexpected payload arity: #{function.arity}, supported only 0 and 1"
                  end
                }
              }

              Log.debug "another step fades: #{state_machine.state_data}" while state_machine.step

              Log.debug 'shut down'
            }
          }
        }
      end
    end
  end
end
