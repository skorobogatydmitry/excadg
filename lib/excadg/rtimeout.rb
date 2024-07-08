# frozen_string_literal: true

module ExcADG
  # simple ractor-safe timeout implementation
  # @param timeout timeout in seconds
  # @param block payload to run with timeout
  module RTimeout
    def await timeout: nil, &block
      return block.call if timeout.nil? || timeout.zero?

      timed_out = false
      Thread.report_on_exception = false
      payload = Thread.new { Thread.current[:result] = block.call }
      Thread.new {
        sleep timeout
        payload.kill
        timed_out = true
      }

      payload.join
      timed_out ? raise(TimedOutError) : payload[:result]
    end
    module_function :await

    class TimedOutError < StandardError; end
  end
end
