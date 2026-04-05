# frozen_string_literal: true

module MarshalMd
  class ObjectRegistry
    def initialize
      @id_to_anchor = {} # object_id => "obj_1"
      @anchor_to_obj = {} # "obj_1" => object
      @counter = 0
    end

    # Dump mode: register an object, return its anchor name
    def register(obj)
      oid = obj.object_id
      return @id_to_anchor[oid] if @id_to_anchor.key?(oid)

      @counter += 1
      anchor = "obj_#{@counter}"
      @id_to_anchor[oid] = anchor
      anchor
    end

    def anchor_for(obj)
      @id_to_anchor[obj.object_id]
    end

    def registered?(obj)
      @id_to_anchor.key?(obj.object_id)
    end

    # Load mode: store anchor -> object mapping
    def store(anchor, obj)
      @anchor_to_obj[anchor] = obj
    end

    def resolve(anchor)
      unless @anchor_to_obj.key?(anchor)
        raise ArgumentError, "undefined reference: *#{anchor}"
      end

      @anchor_to_obj[anchor]
    end
  end
end
