# frozen_string_literal: true

module ExcADG
  # collection of simple assertions
  module Assertions
    class << self
      # asserts that all vars are instances of one of the clss
      # @param vars array or a single variable to check
      # @param clss array or a single class to check against
      # @raise StandardError if any of vars are not of clss
      def is_a? vars, clss
        return if vars.is_a?(Array) && clss == Array

        clss = [clss] unless clss.is_a? Array
        vars = [vars] unless vars.is_a? Array
        wrong_vars = vars.reject { |var|
          clss.any? { |cls|
            var.is_a? cls
          }
        }
        raise "vars #{wrong_vars} not of classes #{clss}" unless wrong_vars.empty?
      end
    end
  end
end
