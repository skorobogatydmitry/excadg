# frozen_string_literal: true

require 'timeout'

require_relative 'data_store'
require_relative 'log'
require_relative 'request'
require_relative 'vertex'

module ExcADG
  # handle requests sending/receiving though Ractor's interface
  module Broker
    class << self
      attr_reader :data_store, :vtracker

      # is used from vertices to send reaqests to the broker
      # @return data received in response from the main ractor
      # @raise StandardError if response is a StandardError
      # @raise CantSendRequest if sending request failed for any reason
      def ask request
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

      # start requests broker for vertices in a separated thread
      # @param track {Boolean} whether to track execution graph
      # @return the thread started
      def run track: false
        @data_store ||= DataStore.new
        @vtracker ||= track ? VTracker.new : nil
        @broker = Thread.new { loop { process_request } } unless @broker&.alive?

        at_exit {
          Log.info 'shut down broker'
          @broker.kill
        }

        Log.info 'broker is started'
        @broker
      end

      # makes a thread to wait for all known vertices to reach a final state;
      # it expects some vertices to be started in the outer scope,
      # so it waits even if there are no vertices at all yet
      # @param timeout total waiting timeout in seconds, nil means wait forever
      # @param period time between vertices state check
      def wait_all timeout: 60, period: 1
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

      # waits for an incoming request,
      # validates request type and content
      # then makes and sends an answer
      def process_request
        begin
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
        Log.debug 'message processed'
      end
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
