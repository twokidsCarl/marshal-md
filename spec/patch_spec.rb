# frozen_string_literal: true

require "spec_helper"

# Note: require patch in an isolated context to avoid polluting other tests.
# We test by directly calling MarshalMd::Patch methods.

RSpec.describe "Monkey-patch mode" do
  before(:all) do
    # Save original methods
    @original_dump = ::Marshal.method(:dump)
    @original_load = ::Marshal.method(:load)

    require "marshal-md/patch"
  end

  after(:all) do
    # Restore original Marshal methods
    ::Marshal.define_singleton_method(:dump, @original_dump)
    ::Marshal.define_singleton_method(:load, @original_load)
    # Remove binary aliases if they exist
    if ::Marshal.respond_to?(:binary_dump)
      class << ::Marshal
        remove_method :binary_dump
        remove_method :binary_load
      end
    end
  end

  it "Marshal.dump produces Markdown" do
    md = Marshal.dump(42)
    expect(md).to eq("42 (Integer)")
  end

  it "Marshal.load parses Markdown" do
    md = Marshal.dump("hello")
    expect(Marshal.load(md)).to eq("hello")
  end

  it "Marshal.load auto-detects binary format" do
    binary = Marshal.binary_dump(42)
    expect(binary.b[0, 2]).to eq("\x04\x08".b)
    expect(Marshal.load(binary)).to eq(42)
  end

  it "Marshal.binary_dump produces binary" do
    binary = Marshal.binary_dump([1, 2, 3])
    expect(binary.b[0, 2]).to eq("\x04\x08".b)
  end

  it "Marshal.binary_load reads binary" do
    binary = Marshal.binary_dump({ a: 1 })
    expect(Marshal.binary_load(binary)).to eq({ a: 1 })
  end

  it "round-trips through Markdown via Marshal" do
    data = { name: "Alice", scores: [85, 92, 78] }
    md = Marshal.dump(data)
    result = Marshal.load(md)
    expect(result).to eq(data)
  end
end
