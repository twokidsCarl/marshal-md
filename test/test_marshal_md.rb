# frozen_string_literal: false
#
# Adapts the official CRuby Marshal test suite for MarshalMd.
# Only overrides encode/decode — everything else is the official test code.
#

require "test/unit"
require_relative "../lib/marshal-md"
require_relative "marshaltestlib"

class TestMarshalMd < Test::Unit::TestCase
  include MarshalTestLib

  def encode(o)
    MarshalMd.dump(o)
  end

  def decode(s)
    MarshalMd.load(s)
  end
end
