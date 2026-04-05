# frozen_string_literal: true

require "spec_helper"

RSpec.describe MarshalMd do
  describe ".dump and .load basic types" do
    it "round-trips nil" do
      md = MarshalMd.dump(nil)
      expect(md).to eq("nil")
      expect(MarshalMd.load(md)).to be_nil
    end

    it "round-trips true" do
      md = MarshalMd.dump(true)
      expect(md).to eq("true")
      expect(MarshalMd.load(md)).to eq(true)
    end

    it "round-trips false" do
      md = MarshalMd.dump(false)
      expect(md).to eq("false")
      expect(MarshalMd.load(md)).to eq(false)
    end

    it "round-trips positive integer" do
      md = MarshalMd.dump(42)
      expect(md).to eq("42")
      expect(MarshalMd.load(md)).to eq(42)
    end

    it "round-trips negative integer" do
      md = MarshalMd.dump(-100)
      expect(md).to eq("-100")
      expect(MarshalMd.load(md)).to eq(-100)
    end

    it "round-trips zero" do
      expect(MarshalMd.load(MarshalMd.dump(0))).to eq(0)
    end

    it "round-trips large integer" do
      big = 10**20
      expect(MarshalMd.load(MarshalMd.dump(big))).to eq(big)
    end

    it "round-trips float" do
      md = MarshalMd.dump(3.14)
      expect(md).to eq("3.14")
      expect(MarshalMd.load(md)).to eq(3.14)
    end

    it "round-trips Float::INFINITY" do
      md = MarshalMd.dump(Float::INFINITY)
      expect(md).to eq("Infinity")
      expect(MarshalMd.load(md)).to eq(Float::INFINITY)
    end

    it "round-trips -Float::INFINITY" do
      md = MarshalMd.dump(-Float::INFINITY)
      expect(md).to eq("-Infinity")
      expect(MarshalMd.load(md)).to eq(-Float::INFINITY)
    end

    it "round-trips Float::NAN" do
      md = MarshalMd.dump(Float::NAN)
      expect(md).to eq("NaN")
      expect(MarshalMd.load(md).nan?).to be true
    end

    it "round-trips symbol" do
      md = MarshalMd.dump(:foo)
      expect(md).to eq(":foo")
      expect(MarshalMd.load(md)).to eq(:foo)
    end

    it "round-trips simple string" do
      md = MarshalMd.dump("hello world")
      expect(md).to eq('"hello world"')
      expect(MarshalMd.load(md)).to eq("hello world")
    end

    it "round-trips string with special characters" do
      str = "line1\nline2\ttab\"quote\\backslash"
      result = MarshalMd.load(MarshalMd.dump(str))
      expect(result).to eq(str)
    end

    it "round-trips empty string" do
      expect(MarshalMd.load(MarshalMd.dump(""))).to eq("")
    end

    it "round-trips binary string" do
      str = "\x00\x01\xFF\xFE".b
      md = MarshalMd.dump(str)
      expect(md).to include("base64:")
      result = MarshalMd.load(md)
      expect(result).to eq(str)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end

  describe "compound types" do
    it "round-trips simple array" do
      arr = [1, "two", 3.0]
      md = MarshalMd.dump(arr)
      expect(md).to include("(Array)")
      expect(MarshalMd.load(md)).to eq(arr)
    end

    it "round-trips empty array" do
      expect(MarshalMd.load(MarshalMd.dump([]))).to eq([])
    end

    it "round-trips nested array" do
      arr = [[1, 2], [3, 4]]
      expect(MarshalMd.load(MarshalMd.dump(arr))).to eq(arr)
    end

    it "round-trips simple hash" do
      hash = { name: "Alice", age: 30 }
      md = MarshalMd.dump(hash)
      expect(md).to include("(Hash)")
      expect(MarshalMd.load(md)).to eq(hash)
    end

    it "round-trips empty hash" do
      expect(MarshalMd.load(MarshalMd.dump({}))).to eq({})
    end

    it "round-trips hash with string keys" do
      hash = { "key" => "value", "num" => 42 }
      expect(MarshalMd.load(MarshalMd.dump(hash))).to eq(hash)
    end

    it "round-trips inclusive range" do
      r = 1..10
      md = MarshalMd.dump(r)
      expect(md).to eq("1..10 (Range)")
      expect(MarshalMd.load(md)).to eq(r)
    end

    it "round-trips exclusive range" do
      r = 1...10
      expect(MarshalMd.load(MarshalMd.dump(r))).to eq(r)
    end

    it "round-trips string range" do
      r = "a".."z"
      expect(MarshalMd.load(MarshalMd.dump(r))).to eq(r)
    end

    it "round-trips regexp" do
      r = /^\d+$/
      md = MarshalMd.dump(r)
      expect(md).to include("(Regexp)")
      expect(MarshalMd.load(md)).to eq(r)
    end

    it "round-trips regexp with flags" do
      r = /hello/im
      result = MarshalMd.load(MarshalMd.dump(r))
      expect(result).to eq(r)
      expect(result.options & Regexp::IGNORECASE).not_to eq(0)
      expect(result.options & Regexp::MULTILINE).not_to eq(0)
    end

    it "round-trips time" do
      t = Time.new(2026, 4, 3, 10, 30, 0, "+08:00")
      result = MarshalMd.load(MarshalMd.dump(t))
      expect(result.to_i).to eq(t.to_i)
    end
  end

  describe "readability" do
    it "produces readable output for a simple hash" do
      md = MarshalMd.dump({ name: "Alice", age: 30 })
      expect(md).to include("name:")
      expect(md).to include("Alice")
      expect(md).to include("30")
    end

    it "produces readable output for an array" do
      md = MarshalMd.dump([1, 2, 3])
      expect(md).to include("[")
      expect(md).to include("1")
    end
  end
end
