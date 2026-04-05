# frozen_string_literal: true

require "base64"

module MarshalMd
  class Dumper
    UNDUMPABLE = [Proc, IO, Thread, Binding, Method, UnboundMethod].freeze
    IMMEDIATE_CLASSES = [Integer, Symbol, TrueClass, FalseClass, NilClass].freeze

    # Built-in types that can have subclasses with special handling
    BUILTIN_TYPES = [Array, Hash, String, Regexp, Range, Time].freeze

    def initialize(obj, limit: -1)
      @root = obj
      @limit = limit
      @registry = ObjectRegistry.new
      @needs_anchor = {} # object_id => true
      @scan_stack = {}   # object_id => true (cycle detection)
      @seen = {}         # object_id => true (multi-ref detection)
      @emitted = {}      # object_id => true (pass 2)
    end

    def dump
      check_dumpable!(@root)
      scan(@root)
      @depth_remaining = @limit
      emit(@root, 0).rstrip
    end

    private

    def check_dumpable!(obj)
      UNDUMPABLE.each do |klass|
        if obj.is_a?(klass)
          raise TypeError, "no _dump_data is defined for class #{obj.class}"
        end
      end

      # Singleton classes/methods
      if obj.respond_to?(:singleton_methods) && !obj.singleton_methods(false).empty?
        raise TypeError, "singleton can't be dumped"
      end

      # Singleton class with instance variables or constants
      unless immediate?(obj) || obj.is_a?(Class) || obj.is_a?(Module)
        begin
          sc = obj.singleton_class
          if !sc.instance_variables.empty? || sc.constants(false).any?
            raise TypeError, "singleton can't be dumped"
          end
        rescue TypeError => e
          raise if e.message.include?("singleton can't be dumped")
          # can't define singleton on immediate values — that's fine
        end
      end

      # Special undumpable objects
      if obj.equal?(ARGF) || obj.equal?(ENV)
        raise TypeError, "can't dump #{obj.class}"
      end

      # Anonymous classes and modules
      if obj.is_a?(Class) || obj.is_a?(Module)
        if obj.name.nil? || obj.name.empty?
          raise TypeError, "can't dump anonymous #{obj.is_a?(Class) ? 'Class' : 'Module'} #{obj}"
        end
        # Classes/modules with non-portable names (e.g. defined in singleton classes)
        if obj.name.include?("#<")
          raise TypeError, "can't dump anonymous #{obj.is_a?(Class) ? 'Class' : 'Module'} #{obj}"
        end
      end

      # Instances of anonymous classes
      if obj.class.name.nil? || obj.class.name.empty?
        raise TypeError, "can't dump anonymous class #{obj.class}"
      end

      # Hash with default proc
      if obj.is_a?(Hash) && obj.default_proc
        raise TypeError, "can't dump hash with default proc"
      end
    end

    def immediate?(obj)
      IMMEDIATE_CLASSES.any? { |k| obj.is_a?(k) }
    end

    def builtin_type(obj)
      BUILTIN_TYPES.find { |t| obj.is_a?(t) }
    end

    def subclassed_builtin?(obj)
      bt = builtin_type(obj)
      bt && obj.class != bt
    end

    # Extra instance variables (beyond what the built-in type provides)
    def extra_ivars(obj)
      obj.instance_variables.sort
    end

    def has_extra_ivars?(obj)
      !obj.instance_variables.empty?
    end

    def has_extensions?(obj)
      return false if immediate?(obj)
      begin
        mods = obj.singleton_class.ancestors - obj.class.ancestors
        mods.any? { |m| m.is_a?(Module) && !m.is_a?(Class) }
      rescue TypeError
        false
      end
    end

    def needs_wrapped_format?(obj)
      has_extra_ivars?(obj) || has_extensions?(obj) || subclassed_builtin?(obj)
    end

    # Pass 1: scan object graph to find shared/circular references
    def scan(obj)
      return if immediate?(obj)

      oid = obj.object_id

      if @scan_stack[oid]
        @needs_anchor[oid] = true
        return
      end

      if @seen[oid]
        @needs_anchor[oid] = true
        return
      end

      @seen[oid] = true
      @scan_stack[oid] = true

      case obj
      when String, Float
        # leaf-ish, but may have ivars
        scan_ivars(obj)
      when Regexp
        scan_ivars(obj)
      when Range
        scan(obj.begin) if obj.begin
        scan(obj.end) if obj.end
        scan_ivars(obj)
      when Time
        scan_ivars(obj)
      when Array
        obj.each { |el| scan(el) }
        scan_ivars(obj)
      when Hash
        obj.each { |k, v| scan(k); scan(v) }
        scan_ivars(obj)
      when Struct
        obj.each_pair { |_, v| scan(v) }
        scan_ivars(obj)
      when Class, Module
        # leaf
      else
        if obj.respond_to?(:marshal_dump)
          scan(obj.marshal_dump)
        elsif obj.respond_to?(:_dump)
          # _dump returns a string
        else
          scan_ivars(obj)
        end
      end

      @scan_stack.delete(oid)
    end

    def scan_ivars(obj)
      obj.instance_variables.each do |ivar|
        scan(obj.instance_variable_get(ivar))
      end
    end

    # Pass 2: emit markdown
    def emit(obj, indent)
      check_dumpable!(obj)

      # Depth limit check (Marshal compat: limit >= 0 means limited depth)
      if @depth_remaining == 0 && @limit >= 0
        raise ArgumentError, "exceed depth limit"
      end

      if !immediate?(obj) && @needs_anchor[obj.object_id]
        if @emitted[obj.object_id]
          anchor = @registry.anchor_for(obj) || @registry.register(obj)
          return "#{"  " * indent}*#{anchor} (ref)\n"
        end
        anchor = @registry.register(obj)
        @emitted[obj.object_id] = true
        return emit_anchored(obj, indent, anchor)
      end

      if !immediate?(obj)
        @emitted[obj.object_id] = true
      end

      if @limit >= 0
        @depth_remaining -= 1
        result = emit_value(obj, indent)
        @depth_remaining += 1
        result
      else
        emit_value(obj, indent)
      end
    end

    def emit_anchored(obj, indent, anchor)
      prefix = "  " * indent
      lines = emit_value(obj, indent)
      first_line = lines.lines.first
      rest = lines.lines[1..].join
      stripped = first_line.lstrip
      "#{prefix}&#{anchor} #{stripped}#{rest}"
    end

    def emit_value(obj, indent)
      prefix = "  " * indent

      case obj
      when NilClass
        "#{prefix}nil (NilClass)\n"
      when TrueClass
        "#{prefix}true (Boolean)\n"
      when FalseClass
        "#{prefix}false (Boolean)\n"
      when Integer
        "#{prefix}#{obj} (Integer)\n"
      when Float
        "#{prefix}#{format_float(obj)} (Float)\n"
      when Complex
        "#{prefix}(#{obj.real}+#{obj.imaginary}i) (Complex)\n"
      when Rational
        "#{prefix}#{obj.numerator}/#{obj.denominator} (Rational)\n"
      when Symbol
        "#{prefix}:#{obj} (Symbol)\n"
      when Class
        "#{prefix}#{obj.name} (Class)\n"
      when Module
        "#{prefix}#{obj.name} (Module)\n"
      when Struct
        emit_struct(obj, indent)
      when Range
        emit_range(obj, indent)
      when Regexp
        emit_regexp(obj, indent)
      when Time
        emit_time(obj, indent)
      when String
        emit_string(obj, indent)
      when Array
        emit_array(obj, indent)
      when Hash
        emit_hash(obj, indent)
      else
        emit_custom(obj, indent)
      end
    end

    def format_float(f)
      if f.infinite? == 1
        "Infinity"
      elsif f.infinite? == -1
        "-Infinity"
      elsif f.nan?
        "NaN"
      elsif f.zero? && (1.0 / f) == -Float::INFINITY
        "-0.0"
      else
        # Use enough precision to round-trip
        f.to_s
      end
    end

    def format_string_value(str, bare: false)
      if str.encoding == Encoding::ASCII_8BIT
        encoded = Base64.strict_encode64(str)
        "base64:#{encoded} (String, ASCII-8BIT, #{str.bytesize} bytes)"
      elsif str.encoding != Encoding::UTF_8 && str.encoding != Encoding::US_ASCII
        begin
          utf8_str = str.encode(Encoding::UTF_8)
          "\"#{escape_string(utf8_str)}\" (String, #{str.encoding})"
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          encoded = Base64.strict_encode64(str)
          "base64:#{encoded} (String, #{str.encoding}, #{str.bytesize} bytes)"
        end
      else
        bare ? "\"#{escape_string(str)}\"" : "\"#{escape_string(str)}\" (String)"
      end
    end

    def escape_string(str)
      str.gsub("\\", "\\\\\\\\")
         .gsub("\"", "\\\"")
         .gsub("\n", "\\n")
         .gsub("\r", "\\r")
         .gsub("\t", "\\t")
         .gsub(/[\x00-\x1f]/) { |c| "\\x#{c.ord.to_s(16).rjust(2, '0')}" }
    end

    # Bare inline representation for use inside [...] and {...} and after @ivar:
    def inline_value(obj)
      # Check for reference first (for any non-immediate that's already emitted)
      if !immediate?(obj) && @needs_anchor[obj.object_id] && @emitted[obj.object_id]
        anchor = @registry.anchor_for(obj)
        return "*#{anchor} (ref)"
      end

      case obj
      when NilClass   then "nil"
      when TrueClass  then "true"
      when FalseClass then "false"
      when Integer    then obj.to_s
      when Float      then format_float(obj)
      when Symbol     then ":#{obj}"
      when String     then format_string_value(obj, bare: true)
      else
        nil # not inlineable
      end
    end

    def simple_value?(obj)
      return false if !immediate?(obj) && has_extensions?(obj)
      case obj
      when NilClass, TrueClass, FalseClass, Integer, Float, Symbol
        true
      when String
        !has_extra_ivars?(obj) && obj.encoding != Encoding::ASCII_8BIT && !obj.include?("\n")
      else
        false
      end
    end

    def all_simple?(arr)
      arr.all? { |el| simple_value?(el) || (el.is_a?(String) && !el.include?("\n")) }
    end

    # --- String ---
    def emit_string(obj, indent)
      prefix = "  " * indent
      class_name = obj.class.name
      ivars = extra_ivars(obj)

      if needs_wrapped_format?(obj)
        result = "#{prefix}#<#{class_name}> (#{class_name})\n"
        result += "#{prefix}  __value__: #{format_string_value(obj)}\n"
        result += emit_extensions_str(obj, indent + 1)
        ivars.each do |ivar|
          val = obj.instance_variable_get(ivar)
          result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
        end
        result
      else
        "#{prefix}#{format_string_value(obj)}\n"
      end
    end

    # --- Array ---
    def emit_array(obj, indent)
      prefix = "  " * indent
      class_name = obj.class.name
      ivars = extra_ivars(obj)
      is_subclass = class_name != "Array"

      if needs_wrapped_format?(obj)
        result = "#{prefix}#<#{class_name}> (#{class_name})\n"
        result += "#{prefix}  __elements__:\n"
        if obj.empty?
          result += "#{prefix}    [] (Array)\n"
        else
          result += "#{prefix}    (Array)\n"
          obj.each { |el| result += emit(el, indent + 3) }
        end
        result += emit_extensions_str(obj, indent + 1)
        ivars.each do |ivar|
          val = obj.instance_variable_get(ivar)
          result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
        end
        result
      else
        emit_simple_array(obj, indent)
      end
    end

    def emit_simple_array(obj, indent)
      prefix = "  " * indent
      if obj.empty?
        return "#{prefix}[] (Array)\n"
      end

      if all_simple?(obj) && obj.sum { |el| (inline_value(el) || "").length + 2 } < 80
        items = obj.map { |el| inline_value(el) }.join(", ")
        "#{prefix}[#{items}] (Array)\n"
      else
        result = "#{prefix}(Array)\n"
        obj.each { |el| result += emit(el, indent + 1) }
        result
      end
    end

    # --- Hash ---
    def emit_hash(obj, indent)
      prefix = "  " * indent
      class_name = obj.class.name
      ivars = extra_ivars(obj)
      is_subclass = class_name != "Hash"
      has_default = !obj.default.nil?

      if needs_wrapped_format?(obj) || has_default
        result = "#{prefix}#<#{class_name}> (#{class_name})\n"
        if has_default
          result += emit_ivar(prefix + "  ", "__default__", obj.default, indent + 1)
        end
        result += "#{prefix}  __entries__:\n"
        if obj.empty?
          result += "#{prefix}    {} (Hash)\n"
        else
          result += "#{prefix}    (Hash)\n"
          obj.each do |k, v|
            iv = inline_value(v)
            ik = inline_value(k)
            if ik && iv
              result += "#{prefix}      #{ik} => #{iv}\n"
            elsif ik
              result += "#{prefix}      #{ik} =>\n"
              result += emit(v, indent + 4)
            else
              result += "#{prefix}      (entry)\n"
              result += emit(k, indent + 4)
              result += "#{prefix}        =>\n"
              result += emit(v, indent + 4)
            end
          end
        end
        result += emit_extensions_str(obj, indent + 1)
        ivars.each do |ivar|
          val = obj.instance_variable_get(ivar)
          result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
        end
        result
      else
        emit_simple_hash(obj, indent)
      end
    end

    def emit_simple_hash(obj, indent)
      prefix = "  " * indent
      if obj.empty?
        return "#{prefix}{} (Hash)\n"
      end

      if obj.all? { |k, v| k.is_a?(Symbol) && simple_value?(v) }
        pairs = obj.map { |k, v| "#{k}: #{inline_value(v)}" }.join(", ")
        candidate = "{#{pairs}} (Hash)"
        if candidate.length < 80
          return "#{prefix}#{candidate}\n"
        end
      end

      result = "#{prefix}(Hash)\n"
      obj.each do |k, v|
        ik = inline_value(k)
        iv = inline_value(v)
        if ik && iv
          result += "#{prefix}  #{ik} => #{iv}\n"
        elsif ik
          result += "#{prefix}  #{ik} =>\n"
          result += emit(v, indent + 2)
        else
          result += "#{prefix}  (entry)\n"
          result += emit(k, indent + 2)
          result += "#{prefix}    =>\n"
          result += emit(v, indent + 2)
        end
      end
      result
    end

    # --- Range ---
    def emit_range(obj, indent)
      prefix = "  " * indent
      class_name = obj.class.name
      ivars = extra_ivars(obj)
      is_subclass = class_name != "Range"
      dots = obj.exclude_end? ? "..." : ".."

      if is_subclass || !ivars.empty?
        result = "#{prefix}#<#{class_name}> (#{class_name})\n"
        result += "#{prefix}  __begin__:\n"
        result += emit(obj.begin, indent + 2) if obj.begin
        result += "#{prefix}  __end__:\n"
        result += emit(obj.end, indent + 2) if obj.end
        result += "#{prefix}  __exclude_end__: #{obj.exclude_end?}\n"
        ivars.each do |ivar|
          val = obj.instance_variable_get(ivar)
          result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
        end
        result
      else
        ib = inline_value(obj.begin)
        ie = inline_value(obj.end)
        if ib && ie
          "#{prefix}#{ib}#{dots}#{ie} (Range)\n"
        else
          result = "#{prefix}(Range)\n"
          result += "#{prefix}  __begin__:\n"
          result += emit(obj.begin, indent + 2) if obj.begin
          result += "#{prefix}  __end__:\n"
          result += emit(obj.end, indent + 2) if obj.end
          result += "#{prefix}  __exclude_end__: #{obj.exclude_end?}\n"
          result
        end
      end
    end

    # --- Regexp ---
    def emit_regexp(obj, indent)
      prefix = "  " * indent
      class_name = obj.class.name
      ivars = extra_ivars(obj)
      is_subclass = class_name != "Regexp"

      flags = ""
      flags += "i" if (obj.options & Regexp::IGNORECASE) != 0
      flags += "x" if (obj.options & Regexp::EXTENDED) != 0
      flags += "m" if (obj.options & Regexp::MULTILINE) != 0

      if is_subclass || !ivars.empty?
        result = "#{prefix}#<#{class_name}> (#{class_name})\n"
        result += "#{prefix}  __pattern__: /#{obj.source}/#{flags} (Regexp)\n"
        ivars.each do |ivar|
          val = obj.instance_variable_get(ivar)
          result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
        end
        result
      else
        "#{prefix}/#{obj.source}/#{flags} (Regexp)\n"
      end
    end

    # --- Time ---
    def emit_time(obj, indent)
      prefix = "  " * indent
      class_name = obj.class.name
      ivars = extra_ivars(obj)
      is_subclass = class_name != "Time"

      # Use enough precision for usec round-trip
      time_str = "#{obj.strftime('%Y-%m-%d %H:%M:%S')}.#{obj.usec.to_s.rjust(6, '0')} #{obj.strftime('%z')}"

      if is_subclass || !ivars.empty?
        result = "#{prefix}#<#{class_name}> (#{class_name})\n"
        result += "#{prefix}  __time__: #{time_str} (Time)\n"
        ivars.each do |ivar|
          val = obj.instance_variable_get(ivar)
          result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
        end
        result
      else
        "#{prefix}#{time_str} (Time)\n"
      end
    end

    # --- Struct ---
    def emit_struct(obj, indent)
      # If struct has marshal_dump, use custom object path
      if obj.respond_to?(:marshal_dump)
        return emit_custom(obj, indent)
      end

      prefix = "  " * indent
      class_name = obj.class.name
      ivars = extra_ivars(obj)

      result = "#{prefix}#<#{class_name}> (#{class_name}, Struct)\n"
      obj.each_pair do |member, val|
        result += emit_ivar(prefix + "  ", member.to_s, val, indent + 1)
      end
      result += emit_extensions_str(obj, indent + 1)
      ivars.each do |ivar|
        val = obj.instance_variable_get(ivar)
        result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
      end
      result
    end

    # --- Custom object ---
    def emit_custom(obj, indent)
      prefix = "  " * indent

      if obj.respond_to?(:marshal_dump)
        data = obj.marshal_dump
        result = "#{prefix}#<#{obj.class}> (#{obj.class}, marshal_dump)\n"
        result += emit(data, indent + 1)
        return result
      end

      if obj.respond_to?(:_dump)
        data = obj._dump(-1)
        raise TypeError, "_dump() must return string" unless data.is_a?(String)
        result = "#{prefix}(#{obj.class}, _dump)\n"
        result += "#{prefix}  #{format_string_value(data)}\n"
        return result
      end

      # Exception special handling: store message explicitly
      if obj.is_a?(Exception)
        result = "#{prefix}#<#{obj.class}> (#{obj.class})\n"
        result += "#{prefix}  __message__: #{format_string_value(obj.message, bare: true)}\n" if obj.message
        result += "#{prefix}  __backtrace__:\n"
        if obj.backtrace
          result += emit(obj.backtrace, indent + 2)
        else
          result += "#{prefix}    nil (NilClass)\n"
        end
        result += emit_extensions_str(obj, indent + 1)
        obj.instance_variables.sort.each do |ivar|
          # Skip internal exception ivars that we handle specially
          next if ivar == :@mesg || ivar == :@bt
          val = obj.instance_variable_get(ivar)
          result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
        end
        return result
      end

      result = "#{prefix}#<#{obj.class}> (#{obj.class})\n"
      result += emit_extensions_str(obj, indent + 1)
      obj.instance_variables.sort.each do |ivar|
        val = obj.instance_variable_get(ivar)
        result += emit_ivar(prefix + "  ", ivar, val, indent + 1)
      end
      result
    end

    def emit_ivar(prefix, name, val, parent_indent)
      if simple_value?(val)
        iv = inline_value(val)
        if iv
          return "#{prefix}#{name}: #{iv}\n"
        end
      end
      "#{prefix}#{name}:\n" + emit(val, parent_indent + 1)
    end

    def emit_extensions_str(obj, indent)
      prefix = "  " * indent
      ext = +""
      begin
        sc = obj.singleton_class
        sc_ancestors = sc.ancestors
        class_ancestors = obj.class.ancestors
      rescue TypeError
        return +""
      end

      # Find modules added to singleton class
      # Modules before singleton_class in ancestors are prepended
      # Modules after singleton_class but not in class ancestors are extended
      sc_idx = sc_ancestors.index(sc)
      return +""  unless sc_idx

      prepended = sc_ancestors[0...sc_idx].select { |m| m.is_a?(Module) && !m.is_a?(Class) && !class_ancestors.include?(m) }
      extended = sc_ancestors[(sc_idx + 1)..].select { |m| m.is_a?(Module) && !m.is_a?(Class) && !class_ancestors.include?(m) }

      # Emit in reverse so they apply in correct order during load
      extended.reverse.each do |mod|
        if mod.name.nil? || mod.name.empty?
          raise TypeError, "can't dump anonymous module"
        end
        ext << "#{prefix}__extend__: #{mod.name}\n"
      end

      prepended.reverse.each do |mod|
        if mod.name.nil? || mod.name.empty?
          raise TypeError, "can't dump anonymous module"
        end
        ext << "#{prefix}__prepend__: #{mod.name}\n"
      end

      ext
    end
  end
end
