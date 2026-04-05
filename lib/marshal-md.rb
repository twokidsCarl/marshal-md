# frozen_string_literal: true

require_relative "marshal-md/version"
require_relative "marshal-md/object_registry"
require_relative "marshal-md/dumper"
require_relative "marshal-md/loader"

module MarshalMd
  def self.dump(obj, io = nil)
    md = Dumper.new(obj).dump
    if io
      io.write(md)
      io
    else
      md
    end
  end

  def self.load(source)
    md = source.respond_to?(:read) ? source.read : source
    Loader.new(md).load
  end
end
