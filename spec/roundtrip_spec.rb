# frozen_string_literal: true

require "spec_helper"

class TestUser
  attr_accessor :name, :age

  def initialize(name = nil, age = nil)
    @name = name
    @age = age
  end

  def ==(other)
    other.is_a?(TestUser) && @name == other.name && @age == other.age
  end
end

class TestAddress
  attr_accessor :city, :zip

  def initialize(city = nil, zip = nil)
    @city = city
    @zip = zip
  end

  def ==(other)
    other.is_a?(TestAddress) && @city == other.city && @zip == other.zip
  end
end

class TestMarshalDump
  attr_accessor :data

  def initialize(data = nil)
    @data = data
  end

  def marshal_dump
    @data
  end

  def marshal_load(data)
    @data = data
  end

  def ==(other)
    other.is_a?(TestMarshalDump) && @data == other.data
  end
end

class TestDump
  attr_accessor :value

  def initialize(value = nil)
    @value = value
  end

  def _dump(_depth)
    @value.to_s
  end

  def self._load(str)
    new(str)
  end

  def ==(other)
    other.is_a?(TestDump) && @value == other.value
  end
end

RSpec.describe "Round-trip tests" do
  describe "custom objects" do
    it "round-trips a simple object" do
      user = TestUser.new("Alice", 30)
      result = MarshalMd.load(MarshalMd.dump(user))
      expect(result).to eq(user)
    end

    it "round-trips nested objects" do
      user = TestUser.new("Alice", 30)
      user.instance_variable_set(:@address, TestAddress.new("Tokyo", "100-0001"))
      md = MarshalMd.dump(user)
      result = MarshalMd.load(md)
      expect(result.name).to eq("Alice")
      expect(result.instance_variable_get(:@address).city).to eq("Tokyo")
    end
  end

  describe "shared references" do
    it "preserves object identity for shared arrays" do
      shared = [1, 2, 3]
      container = [shared, shared]
      md = MarshalMd.dump(container)
      result = MarshalMd.load(md)
      expect(result[0]).to eq([1, 2, 3])
      expect(result[0].object_id).to eq(result[1].object_id)
    end

    it "preserves object identity for shared hashes" do
      shared = { a: 1 }
      container = [shared, shared]
      md = MarshalMd.dump(container)
      result = MarshalMd.load(md)
      expect(result[0].object_id).to eq(result[1].object_id)
    end
  end

  describe "circular references" do
    it "handles self-referencing array" do
      arr = [1, 2]
      arr << arr
      md = MarshalMd.dump(arr)
      result = MarshalMd.load(md)
      expect(result[0]).to eq(1)
      expect(result[1]).to eq(2)
      expect(result[2].object_id).to eq(result.object_id)
    end

    it "handles circular hash" do
      hash = { a: 1 }
      hash[:self] = hash
      md = MarshalMd.dump(hash)
      result = MarshalMd.load(md)
      expect(result[:a]).to eq(1)
      expect(result[:self].object_id).to eq(result.object_id)
    end
  end

  describe "marshal_dump / marshal_load protocol" do
    it "round-trips object with marshal_dump" do
      obj = TestMarshalDump.new("important data")
      result = MarshalMd.load(MarshalMd.dump(obj))
      expect(result).to eq(obj)
    end
  end

  describe "_dump / _load protocol" do
    it "round-trips object with _dump" do
      obj = TestDump.new("test_value")
      result = MarshalMd.load(MarshalMd.dump(obj))
      expect(result).to eq(obj)
    end
  end

  describe "complex nested structures" do
    it "round-trips deeply nested data" do
      data = {
        users: [
          TestUser.new("Alice", 25),
          TestUser.new("Bob", 30)
        ],
        metadata: {
          count: 2,
          tags: [:admin, :user],
          active: true
        }
      }
      result = MarshalMd.load(MarshalMd.dump(data))
      expect(result[:users].length).to eq(2)
      expect(result[:users][0].name).to eq("Alice")
      expect(result[:metadata][:count]).to eq(2)
      expect(result[:metadata][:tags]).to eq([:admin, :user])
    end

    it "round-trips mixed type array" do
      arr = [1, "two", 3.0, :four, true, false, nil]
      expect(MarshalMd.load(MarshalMd.dump(arr))).to eq(arr)
    end
  end

  describe "IO support" do
    it "dumps to IO" do
      require "stringio"
      io = StringIO.new
      MarshalMd.dump(42, io)
      io.rewind
      expect(io.read).to eq("42 (Integer)")
    end

    it "loads from IO" do
      require "stringio"
      io = StringIO.new("42 (Integer)")
      expect(MarshalMd.load(io)).to eq(42)
    end
  end
end
