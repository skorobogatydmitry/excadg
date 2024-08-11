# frozen_string_literal: true

require 'logger'

require_relative 'assertions'

module ExcADG
  # logging support
  module Log
    # ractor-based logger,
    # this ractor logger receives messages from other ractors and log them,
    # @param dest what to write logs to, $stdout by default, gets interpret as filename unless IO
    # @param level one of the Logger's log levels
    class RLogger < Ractor
      def self.new dest: $stdout, level: Logger::INFO
        super(dest, level) { |dest, level|
          File.open(dest, 'w+', &:write) unless dest.is_a? IO
          l ||= Logger.new dest
          l.level = level
          l.formatter = proc { |severity, datetime, progname, msg|
            format('%20s | %4s | %-10s || %s', datetime, severity, progname, msg)
          }
          while log = Ractor.receive
            # Expect 3 args - severity, proc name and message
            l.public_send(log.first, log[1], &-> { log.last.to_s + "\n" })
          end
        }
      end
    end

    # default logger
    @main = nil

    # logging is muted by default
    @muted = true

    def self.method_missing(method, *args, &_block)
      return if @muted

      @main ||= RLogger.new
      r = Ractor.current
      @main.send [method, r&.to_s || r.object_id, *args]
    rescue Ractor::ClosedError => e
      # last hope - there is tty
      puts "can't send message to logging ractor: #{e}, message: #{args}"
    end

    def self.respond_to_missing?
      true
    end

    # replaces default logger with a custom one
    # and unmutes logging
    def self.logger new_logger
      Assertions.is_a? new_logger, RLogger
      @main = new_logger
      unmute
    end

    # mute logging by ignoring all incoming log requests
    def self.mute
      @muted = true
    end

    # unmute logging for new messages
    def self.unmute
      @muted = false
    end
  end
end
