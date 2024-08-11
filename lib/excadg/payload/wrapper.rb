# frozen_string_literal: true

require 'tmpdir'
require 'open3'

module ExcADG
  # Payloads that wraps other programs execution
  module Payload::Wrapper
    # runs a binary
    # save its stdout, stderr and exit code to state
    # provides path to temp file with dependencies data JSON in a DEPS_DATAFILE env variable
    class Bin
      include Payload
      def get
        lambda { |deps_data|
            Dir.mktmpdir { |dir|
              Log.debug "temp dir #{} for data is ready"
              stdout, stderr, status = File.open(File.join(dir, 'data.json'), 'w+') { |f|
                f.write JSON.generate deps_data
                f.flush
                Log.debug "data is in #{f.path}"
                Open3.capture3({ 'DEPS_DATAFILE' => f.path }, args)
              }
              Log.debug "payload process finished"
              data = { stdout:, stderr:, exitcode: status.exitstatus }
              raise CommandFailed, data unless status.exitstatus.zero?
              Log.debug "returning data"
              data
            }
        }
      end

      def sanitize args
        raise "arguments should be a String, got #{args}" unless args.is_a? String

        args
      end

      # exception with command execution result
      # for cases when the command fails
      class CommandFailed < StandardError
        # @param data same data as what would be returned by a successful run
        def initialize data
          super 'command failed'
          @data = data
        end

        def to_json(*args)
          @data.to_json(*args)
        end
      end
    end

    # runs a ruby script
    # behaves same as the Bin reg parameters and return data
    class Ruby < Bin
      def sanitize args
        raise "arguments should be a String, got #{args}" unless args.is_a? String

        "ruby #{args}"
      end
    end
  end
end
