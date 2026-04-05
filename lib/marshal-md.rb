# frozen_string_literal: true

require_relative "marshal-md/version"
require_relative "marshal-md/object_registry"
require_relative "marshal-md/dumper"
require_relative "marshal-md/loader"

module MarshalMd
  # Match Marshal.dump signature: dump(obj [, io] [, limit])
  def self.dump(obj, *args)
    io = nil
    limit = -1

    args.each do |arg|
      if arg.respond_to?(:write)
        io = arg
      elsif arg.is_a?(Integer)
        limit = arg
      end
    end

    md = Dumper.new(obj, limit: limit).dump
    if io
      io.write(md)
      io
    else
      md
    end
  end

  # Match Marshal.load signature: load(source [, proc] [, freeze: false])
  def self.load(source, proc = nil, freeze: false)
    md = source.respond_to?(:read) ? source.read : source
    obj = Loader.new(md).load
    obj = apply_proc_recursive(obj, proc) if proc
    deep_freeze(obj) if freeze
    obj
  end

  class << self
    private

    # Apply proc to all deserialized objects, bottom-up.
    # The proc return value replaces the original in parent containers.
    # Uses an identity map so shared references get the same replacement.
    def apply_proc_recursive(obj, proc, visited = {}.compare_by_identity)
      begin
        return visited[obj] if visited.key?(obj)
      rescue TypeError
        # Immediate values
      end

      # Process children first (bottom-up)
      case obj
      when Array
        obj.each_with_index { |el, i| obj[i] = apply_proc_recursive(el, proc, visited) }
      when Hash
        obj.each { |k, v| obj[k] = apply_proc_recursive(v, proc, visited) }
      end

      result = proc.call(obj)

      begin
        visited[obj] = result
      rescue TypeError
        # Immediate values
      end

      result
    end

    def deep_freeze(obj, visited = {}.compare_by_identity)
      return if obj.frozen?

      begin
        return if visited.key?(obj)
        visited[obj] = true
      rescue TypeError
        # Immediate values
      end

      case obj
      when Array
        obj.each { |el| deep_freeze(el, visited) }
      when Hash
        obj.each { |k, v| deep_freeze(k, visited); deep_freeze(v, visited) }
      when String
        # freeze string
      else
        obj.instance_variables.each do |iv|
          deep_freeze(obj.instance_variable_get(iv), visited)
        end
      end

      obj.freeze
    end
  end
end
