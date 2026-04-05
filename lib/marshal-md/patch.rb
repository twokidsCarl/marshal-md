# frozen_string_literal: true

require_relative "../marshal-md"

module MarshalMd
  module Patch
    BINARY_MARSHAL_HEADER = "\x04\x08".b.freeze

    def self.apply!
      ::Marshal.class_eval do
        class << self
          alias_method :binary_dump, :dump
          alias_method :binary_load, :load

          def dump(obj, *args)
            if args.first.respond_to?(:write)
              io = args.first
              md = MarshalMd.dump(obj)
              io.write(md)
              io
            else
              MarshalMd.dump(obj)
            end
          end

          def load(source, *args)
            data = source.respond_to?(:read) ? source.read : source
            if data.b[0, 2] == MarshalMd::Patch::BINARY_MARSHAL_HEADER
              binary_load(data, *args)
            else
              MarshalMd.load(data)
            end
          end
        end
      end
    end
  end
end

MarshalMd::Patch.apply!
