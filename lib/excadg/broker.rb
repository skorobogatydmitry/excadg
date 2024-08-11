# frozen_string_literal: true

require 'timeout'
require 'singleton'

require_relative 'data_store'
require_relative 'log'
require_relative 'request'
require_relative 'vertex'

module ExcADG
  # handle requests sending/receiving though Ractor's interface
  class Broker
    include Singleton

    attr_reader :data_store, :vtracker

    # is used from vertices to send requests to the broker
    # @param request {Request}
    # @return data received in response from the main ractor
    # @raise {StandardError} if response is a StandardError
    # @raise {CantSendRequest} if sending request failed for any reason
    # @raise {UnknownRequestType} if request is not a {Request}
    def self.ask request
      raise UnknownRequestType, request unless request.is_a? Request

      begin
        Ractor.main.send request
      rescue StandardError => e
        raise CantSendRequest, cause: e
      end

      Log.info 'getting response'
      resp = Ractor.receive
      Log.debug "got response #{resp}"
      raise resp if resp.is_a? StandardError

      Log.debug 'returning response'
      resp
    end

    # start processing vertices asks
    # @param track whether to track vertices using {VTracker}
    # @return messanges processing {Thread}
    def start track: true
      @vtracker = VTracker.new if track
      Thread.report_on_exception = false
      @messenger = Thread.new { loop { process_request } }

      at_exit {
        Log.info 'shutting down messenger'
        @messenger.kill
        Log.info 'messenger is stut down'
      }

      Log.info 'broker is started'
      @messenger
    end

    # stop processing vertices asks
    # usually follows {#wait_all}
    def teardown
      return if @messenger.nil?

      @messenger.kill while @messenger.alive?
    end

    # makes a thread to wait for all known vertices to reach a final state;
    # it expects some vertices to be started in the outer scope,
    # so it waits even if there are no vertices at all yet
    # @param timeout total waiting timeout in seconds, nil means wait forever
    # @param period time between vertices state check
    # @return {Thread} that waits for all deps, typical usage is `Broker.instance.wait_all.join`
    def wait_all timeout: 60, period: 1
      Thread.report_on_exception = false
      Thread.new {
        Log.info "timeout is #{timeout || '∞'} seconds"
        Timeout.timeout(timeout) {
          loop {
            sleep period
            if @data_store.empty?
              Log.info 'no vertices in data store, keep waiting'
              next
            end
            states = @data_store.to_a.group_by(&:state).keys
            Log.info "vertices in #{states} states exist"
            # that's the only final states for vertices
            break if (states - %i[done failed]).empty?
          }
        }
      }
    end

    private

    def initialize
      @data_store = DataStore.new
    end

    # waits for an incoming request,
    # validates request type and content
    # then constructs and sends an answer
    # does not fail on {StandardError}, logs & sends it back instead to keep running;
    # the other side crashes in this case, causing the {Vertex} to fail, what's still
    # better than crashing the whole messaging
    def process_request
      request = Ractor.receive
      Log.info "received request: #{request}"
      request.self.send case request
                        when Request::GetStateData
                          @vtracker&.track request.self, request.deps
                          request.filter? ? request.deps.collect { |d| @data_store[d] } : @data_store.to_a
                        when Request::Update
                          @data_store << request.data
                          @vtracker&.track request.self
                          true
                        when Request::AddVertex
                          v = Vertex.new payload: request.payload, deps: [request.self]
                          @vtracker&.track v
                          v
                        else
                          raise UnknownRequestType
                        end
    rescue StandardError => e
      # TODO: add threshold
      Log.warn "error on message processing: #{e.class} / #{e.message} / #{e.backtrace}"
      request.self.send RequestProcessingFailed.new cause: e
    end

    class UnknownRequestType < StandardError; end
    class CantSendRequest < StandardError; end

    # error type returned by broker thread in case it failed to process incoming request
    class RequestProcessingFailed < StandardError
      attr_reader :cause_backtrace

      def initialize cause:
        # storing the cause itself could creak messaging, as it could contain non-shareable objects
        super cause.message
        set_backtrace cause.backtrace
      end
    end
  end
end
