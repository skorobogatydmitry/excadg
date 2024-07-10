# frozen_string_literal: true

module ExcADG
  # complex vertex timeout to carry fine-grained timeouts
  class VTimeout
    attr_reader :global, :payload, :deps

    # @param global timeout for the whole vertex in seconds
    # @param deps for how long to wait for deps to complete in seconds
    # @param payload how long to wait for payload in seconds
    def initialize payload: nil, deps: nil, global: nil
      if !global.nil? && global < (deps || 0) + (payload || 0) && (global < deps + payload)
        raise "global timeout (#{global}) is less than sum of deps (#{deps}) and payload (#{payload}) timeouts"
      end

      @global = global
      @deps = deps
      @payload = payload
    end
  end
end
