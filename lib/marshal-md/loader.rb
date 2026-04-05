# frozen_string_literal: true

require "base64"
require "time"

module MarshalMd
  class Loader
    Line = Struct.new(:indent, :text, :lineno)

    def initialize(md)
      @lines = tokenize(md)
      @pos = 0
      @registry = ObjectRegistry.new
    end

    def load
      parse_value(0)
    end

    private

    def tokenize(md)
      lines = []
      md.each_line.with_index do |raw, i|
        next if raw.strip.empty?
        stripped = raw.rstrip
        spaces = stripped.length - stripped.lstrip.length
        indent = spaces / 2
        lines << Line.new(indent, stripped.lstrip, i + 1)
      end
      lines
    end

    def current_line
      @lines[@pos]
    end

    def advance
      @pos += 1
    end

    def eof?
      @pos >= @lines.length
    end

    def parse_value(expected_indent)
      return nil if eof?

      line = current_line
      text = line.text

      # Reference
      if text =~ /^\*(\w+) \(ref\)$/
        advance
        return @registry.resolve($1)
      end

      # Anchor prefix
      if text =~ /^&(\w+) (.+)$/
        anchor = $1
        rest = $2
        return parse_anchored(anchor, rest, line.indent)
      end

      parse_unanchored(text, line)
    end

    def parse_unanchored(text, line)
      # nil
      if text == "nil (NilClass)"
        advance
        return nil
      end

      # Boolean
      if text == "true (Boolean)"
        advance
        return true
      end
      if text == "false (Boolean)"
        advance
        return false
      end

      # Integer
      if text =~ /^(-?\d+) \(Integer\)$/
        advance
        return $1.to_i
      end

      # Float
      if text =~ /^(-?(?:Infinity|NaN|0\.0|[\d.]+(?:e[+-]?\d+)?)) \(Float\)$/i
        advance
        return parse_float_value($1)
      end

      # Symbol
      if text =~ /^:(.+) \(Symbol\)$/
        advance
        return $1.to_sym
      end

      # Complex
      if text =~ /^\((-?[\d.]+)\+(-?[\d.]+)i\) \(Complex\)$/
        advance
        return Complex($1.include?('.') ? $1.to_f : $1.to_i, $2.include?('.') ? $2.to_f : $2.to_i)
      end

      # Rational
      if text =~ /^(-?\d+)\/(-?\d+) \(Rational\)$/
        advance
        return Rational($1.to_i, $2.to_i)
      end

      # Class
      if text =~ /^(.+) \(Class\)$/
        advance
        return resolve_class($1)
      end

      # Module
      if text =~ /^(.+) \(Module\)$/
        advance
        return resolve_class($1)
      end

      # Base64 string
      if text =~ /^base64:(\S+) \(String, (.+?), (\d+) bytes\)$/
        advance
        return Base64.strict_decode64($1)
      end

      # String with encoding
      if text =~ /^"(.*)" \(String, (.+)\)$/
        advance
        str = unescape($1)
        return str.encode($2)
      end

      # String (UTF-8)
      if text =~ /^"(.*)" \(String\)$/
        advance
        return unescape($1)
      end

      # Inline Range
      if text =~ /^(.+?)(\.\.\.?)(.+) \(Range\)$/
        advance
        range_begin = parse_inline_value($1)
        range_end = parse_inline_value($3)
        exclusive = $2 == "..."
        return Range.new(range_begin, range_end, exclusive)
      end

      # Multi-line Range
      if text == "(Range)"
        advance
        return parse_multiline_range(line.indent)
      end

      # Regexp
      if text =~ /^\/(.*)\/([imx]*) \(Regexp\)$/
        advance
        return build_regexp($1, $2)
      end

      # Time with usec
      if text =~ /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.(\d+) ([+-]\d{4}) \(Time\)$/
        advance
        return parse_time_with_usec($1, $2, $3)
      end

      # Time without usec
      if text =~ /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}) \(Time\)$/
        advance
        return Time.parse($1)
      end

      # Inline Array
      if text =~ /^\[.*\] \(Array\)$/
        advance
        return parse_inline_array(text)
      end

      # Empty array
      if text == "[] (Array)"
        advance
        return []
      end

      # Multi-line Array
      if text == "(Array)"
        advance
        return parse_multiline_array(line.indent)
      end

      # Inline Hash
      if text =~ /^\{.*\} \(Hash\)$/
        advance
        return parse_inline_hash(text)
      end

      # Empty hash
      if text == "{} (Hash)"
        advance
        return {}
      end

      # Multi-line Hash
      if text == "(Hash)"
        advance
        return parse_multiline_hash(line.indent)
      end

      # Struct
      if text =~ /^#<(.+?)> \((.+?), Struct\)$/
        klass_name = $2
        advance
        return parse_struct(klass_name, line.indent)
      end

      # Custom object with marshal_dump
      if text =~ /^#<(.+?)> \((.+?), marshal_dump\)$/
        klass_name = $2
        advance
        return parse_marshal_dump_object(klass_name, line.indent)
      end

      # Custom object with _dump
      if text =~ /^\((.+?), _dump\)$/
        klass_name = $1
        advance
        return parse_dump_object(klass_name, line.indent)
      end

      # Custom object (including subclassed built-ins)
      if text =~ /^#<(.+?)> \((.+?)\)$/
        klass_name = $2
        advance
        return parse_custom_object(klass_name, line.indent)
      end

      raise "Unexpected format at line #{line.lineno}: #{text}"
    end

    def parse_anchored(anchor, rest, indent)
      # Reference
      if rest =~ /^\*(\w+) \(ref\)$/
        advance
        return @registry.resolve($1)
      end

      # Determine what the rest describes and handle allocation+registration before parsing children

      # Inline Array
      if rest =~ /^\[.*\] \(Array\)$/
        advance
        arr = parse_inline_array(rest)
        @registry.store(anchor, arr)
        return arr
      end

      if rest == "[] (Array)"
        advance
        arr = []
        @registry.store(anchor, arr)
        return arr
      end

      # Multi-line Array
      if rest == "(Array)"
        advance
        arr = []
        @registry.store(anchor, arr)
        parse_multiline_array_into(arr, indent)
        return arr
      end

      # Inline Hash
      if rest =~ /^\{.*\} \(Hash\)$/
        advance
        hash = parse_inline_hash(rest)
        @registry.store(anchor, hash)
        return hash
      end

      if rest == "{} (Hash)"
        advance
        hash = {}
        @registry.store(anchor, hash)
        return hash
      end

      # Multi-line Hash
      if rest == "(Hash)"
        advance
        hash = {}
        @registry.store(anchor, hash)
        parse_multiline_hash_into(hash, indent)
        return hash
      end

      # Struct
      if rest =~ /^#<(.+?)> \((.+?), Struct\)$/
        klass_name = $2
        advance
        klass = resolve_class(klass_name)
        # Allocate and register before parsing members
        obj = klass.allocate
        @registry.store(anchor, obj)
        parse_struct_members_into(obj, klass, indent)
        return obj
      end

      # Custom object with marshal_dump
      if rest =~ /^#<(.+?)> \((.+?), marshal_dump\)$/
        klass_name = $2
        advance
        klass = resolve_class(klass_name)
        obj = klass.allocate
        @registry.store(anchor, obj)
        data = parse_value(indent + 1)
        obj.send(:marshal_load, data)
        return obj
      end

      # Custom object with _dump
      if rest =~ /^\((.+?), _dump\)$/
        klass_name = $1
        advance
        klass = resolve_class(klass_name)
        data = parse_child_string(indent)
        obj = klass._load(data)
        @registry.store(anchor, obj)
        return obj
      end

      # Custom object (including subclassed built-ins)
      if rest =~ /^#<(.+?)> \((.+?)\)$/
        klass_name = $2
        advance
        klass = resolve_class(klass_name)
        obj = allocate_for(klass)
        @registry.store(anchor, obj)
        obj = parse_custom_object_body(obj, klass, indent)
        @registry.store(anchor, obj) # update in case of replacement
        return obj
      end

      # String
      if rest =~ /^"(.*)" \(String(?:, (.+))?\)$/
        advance
        str = unescape($1)
        str = str.encode($2) if $2
        @registry.store(anchor, str)
        return str
      end

      if rest =~ /^base64:(\S+) \(String, (.+?), (\d+) bytes\)$/
        advance
        str = Base64.strict_decode64($1)
        @registry.store(anchor, str)
        return str
      end

      # Float
      if rest =~ /^(-?(?:Infinity|NaN|0\.0|[\d.]+(?:e[+-]?\d+)?)) \(Float\)$/i
        advance
        val = parse_float_value($1)
        @registry.store(anchor, val)
        return val
      end

      # Inline Range
      if rest =~ /^(.+?)(\.\.\.?)(.+) \(Range\)$/
        advance
        range_begin = parse_inline_value($1)
        range_end = parse_inline_value($3)
        exclusive = $2 == "..."
        val = Range.new(range_begin, range_end, exclusive)
        @registry.store(anchor, val)
        return val
      end

      # Multi-line Range
      if rest == "(Range)"
        advance
        val = parse_multiline_range(indent)
        @registry.store(anchor, val)
        return val
      end

      # Regexp
      if rest =~ /^\/(.*)\/([imx]*) \(Regexp\)$/
        advance
        val = build_regexp($1, $2)
        @registry.store(anchor, val)
        return val
      end

      # Time with usec
      if rest =~ /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.(\d+) ([+-]\d{4}) \(Time\)$/
        advance
        val = parse_time_with_usec($1, $2, $3)
        @registry.store(anchor, val)
        return val
      end

      # Time without usec
      if rest =~ /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}) \(Time\)$/
        advance
        val = Time.parse($1)
        @registry.store(anchor, val)
        return val
      end

      raise "Unexpected anchored format: &#{anchor} #{rest}"
    end

    # --- Type-specific parsers ---

    def parse_float_value(str)
      case str
      when "Infinity" then Float::INFINITY
      when "-Infinity" then -Float::INFINITY
      when "NaN" then Float::NAN
      when "-0.0" then -0.0
      else str.to_f
      end
    end

    def parse_time_with_usec(datetime, usec_str, zone)
      tz = zone
      if tz =~ /^([+-])(\d{2})(\d{2})$/
        tz = "#{$1}#{$2}:#{$3}"
      end
      t = Time.parse("#{datetime} #{zone}")
      usec = usec_str.to_i
      # Use Rational for exact usec precision
      sec_with_usec = t.sec + Rational(usec, 1_000_000)
      Time.new(t.year, t.month, t.day, t.hour, t.min, sec_with_usec, tz)
    end

    def build_regexp(source, flags_str)
      flags = 0
      flags |= Regexp::IGNORECASE if flags_str.include?("i")
      flags |= Regexp::EXTENDED if flags_str.include?("x")
      flags |= Regexp::MULTILINE if flags_str.include?("m")
      Regexp.new(source, flags)
    end

    def parse_multiline_range(parent_indent)
      rb = nil
      re = nil
      excl = false

      while !eof? && current_line.indent > parent_indent
        text = current_line.text
        if text == "__begin__:"
          advance
          rb = parse_value(current_line&.indent || parent_indent + 2)
        elsif text == "__end__:"
          advance
          re = parse_value(current_line&.indent || parent_indent + 2)
        elsif text =~ /^__exclude_end__: (.+)$/
          excl = $1 == "true"
          advance
        else
          break
        end
      end

      Range.new(rb, re, excl)
    end

    def parse_struct(klass_name, parent_indent)
      klass = resolve_class(klass_name)
      obj = klass.allocate
      parse_struct_members_into(obj, klass, parent_indent)
      obj
    end

    def parse_struct_members_into(obj, klass, parent_indent)
      members = klass.members
      while !eof? && current_line.indent > parent_indent
        text = current_line.text

        # __extend__ directive
        if text =~ /^__extend__: (.+)$/
          mod = resolve_class($1)
          obj.extend(mod)
          advance
          next
        end

        # __prepend__ directive
        if text =~ /^__prepend__: (.+)$/
          mod = resolve_class($1)
          obj.singleton_class.prepend(mod)
          advance
          next
        end

        if text =~ /^(\w+): (.+)$/
          name = $1
          value_text = $2
          advance
          if name.start_with?("@")
            val = parse_inline_value(value_text)
            obj.instance_variable_set(name, val)
          elsif members.include?(name.to_sym)
            val = parse_inline_value(value_text)
            obj[name.to_sym] = val
          end
        elsif text =~ /^(\w+):$/
          name = $1
          advance
          val = parse_value(current_line&.indent || parent_indent + 2)
          if name.start_with?("@")
            obj.instance_variable_set(name, val)
          elsif members.include?(name.to_sym)
            obj[name.to_sym] = val
          end
        elsif text =~ /^(@\w+): (.+)$/
          ivar = $1
          advance
          val = parse_inline_value($2)
          obj.instance_variable_set(ivar, val)
        elsif text =~ /^(@\w+):$/
          ivar = $1
          advance
          val = parse_value(current_line&.indent || parent_indent + 2)
          obj.instance_variable_set(ivar, val)
        else
          break
        end
      end
    end

    def parse_marshal_dump_object(klass_name, parent_indent)
      klass = resolve_class(klass_name)
      obj = klass.allocate
      data = parse_value(parent_indent + 1)
      obj.send(:marshal_load, data)
      obj
    end

    def parse_dump_object(klass_name, parent_indent)
      klass = resolve_class(klass_name)
      data = parse_child_string(parent_indent)
      klass._load(data)
    end

    def parse_child_string(parent_indent)
      if !eof? && current_line.indent > parent_indent
        text = current_line.text
        if text =~ /^"(.*)" \(String(?:, (.+))?\)$/
          advance
          str = unescape($1)
          str = str.encode($2) if $2
          return str
        elsif text =~ /^base64:(\S+) \(String, (.+?), (\d+) bytes\)$/
          advance
          return Base64.strict_decode64($1)
        else
          return parse_value(parent_indent + 1)
        end
      end
      nil
    end

    def allocate_for(klass)
      if klass <= Array
        klass == Array ? [] : klass.allocate
      elsif klass <= Hash
        klass == Hash ? {} : klass.allocate
      elsif klass <= String
        klass.new("")
      elsif klass <= Range
        klass.allocate
      elsif klass <= Regexp
        klass.allocate
      elsif klass <= Time
        klass.allocate
      else
        klass.allocate
      end
    end

    def parse_custom_object(klass_name, parent_indent)
      klass = resolve_class(klass_name)
      obj = allocate_for(klass)
      parse_custom_object_body(obj, klass, parent_indent)
    end

    def parse_custom_object_body(obj, klass, parent_indent)
      @_pending_time_replacement = nil
      @_pending_regexp_replacement = nil
      @_pending_range_begin = nil
      @_pending_range_end = nil
      @_pending_range_excl = false

      saved_ivars = []
      parse_custom_body_into(obj, klass, parent_indent)

      # Reconstruct Time subclass - collect ivars from allocated obj first
      if @_pending_time_replacement && klass <= Time
        t = @_pending_time_replacement
        ivars = obj.instance_variables.map { |iv| [iv, obj.instance_variable_get(iv)] }
        obj = klass.at(t.to_r)
        obj = obj.getlocal(t.utc_offset)
        ivars.each { |iv, val| obj.instance_variable_set(iv, val) }
      end

      # Reconstruct Regexp subclass
      if @_pending_regexp_replacement && klass <= Regexp
        r = @_pending_regexp_replacement
        ivars = obj.instance_variables.map { |iv| [iv, obj.instance_variable_get(iv)] }
        obj = klass.allocate
        # Use Regexp#initialize from the base class
        Regexp.instance_method(:initialize).bind(obj).call(r.source, r.options)
        ivars.each { |iv, val| obj.instance_variable_set(iv, val) }
      end

      # Reconstruct Range subclass
      if @_pending_range_begin || @_pending_range_end
        if klass <= Range
          # Initialize the existing object in-place to preserve identity (for circular refs)
          Range.instance_method(:initialize).bind(obj).call(@_pending_range_begin, @_pending_range_end, @_pending_range_excl)
        end
      end

      obj
    end

    def parse_custom_body_into(obj, klass, parent_indent)
      while !eof? && current_line.indent > parent_indent
        text = current_line.text

        # __extend__ directive
        if text =~ /^__extend__: (.+)$/
          mod = resolve_class($1)
          obj.extend(mod)
          advance
          next
        end

        # __prepend__ directive
        if text =~ /^__prepend__: (.+)$/
          mod = resolve_class($1)
          obj.singleton_class.prepend(mod)
          advance
          next
        end

        # __message__ for exceptions
        if text =~ /^__message__: (.+)$/
          advance
          msg = parse_inline_value($1)
          if obj.is_a?(Exception)
            # Use Exception's initialize to set message without triggering subclass initialize
            Exception.instance_method(:initialize).bind(obj).call(msg)
          end
          next
        end

        # __backtrace__ for exceptions
        if text == "__backtrace__:"
          advance
          if !eof? && current_line.indent > parent_indent + 1
            bt = parse_value(current_line.indent)
            obj.set_backtrace(bt) if obj.is_a?(Exception) && bt
          end
          next
        end

        # __value__ for subclassed strings
        if text =~ /^__value__: (.+)$/
          advance
          str_val = parse_inline_value($1)
          if obj.is_a?(String)
            obj.replace(str_val)
          end
          next
        end

        # __elements__ for subclassed arrays
        if text == "__elements__:"
          advance
          if !eof? && current_line.indent > parent_indent + 1
            ct = current_line.text
            if ct =~ /^\[.*\] \(Array\)$/ || ct == "[] (Array)"
              elements = parse_value(current_line.indent)
            elsif ct == "(Array)"
              advance
              elements = []
              while !eof? && current_line.indent > parent_indent + 2
                elements << parse_value(current_line.indent)
              end
            else
              elements = []
            end
            if obj.is_a?(Array)
              elements.each { |el| obj << el }
            end
          end
          next
        end

        # __entries__ for subclassed hashes
        if text == "__entries__:"
          advance
          if !eof? && current_line.indent > parent_indent + 1
            ct = current_line.text
            if ct =~ /^\{.*\} \(Hash\)$/ || ct == "{} (Hash)"
              entries = parse_value(current_line.indent)
            elsif ct == "(Hash)"
              advance
              entries = {}
              parse_multiline_hash_into(entries, current_line ? current_line.indent - 1 : parent_indent + 2)
            else
              entries = {}
            end
            if obj.is_a?(Hash)
              entries.each { |k, v| obj[k] = v }
            end
          end
          next
        end

        # __default__ for hashes
        if text =~ /^__default__: (.+)$/
          advance
          val = parse_inline_value($1)
          obj.default = val if obj.is_a?(Hash)
          next
        end
        if text == "__default__:"
          advance
          val = parse_value(current_line&.indent || parent_indent + 2)
          obj.default = val if obj.is_a?(Hash)
          next
        end

        # __time__ for subclassed Time
        if text =~ /^__time__: (.+) \(Time\)$/
          time_str = $1
          advance
          if time_str =~ /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.(\d+) ([+-]\d{4})$/
            t = parse_time_with_usec($1, $2, $3)
          else
            t = Time.parse(time_str)
          end
          # For Time subclass: replace the allocated object with a proper one
          if obj.is_a?(Time)
            # We can't modify an allocated Time in place, so we need
            # to re-create it. The caller should use the returned object.
            @_pending_time_replacement = t
          end
          next
        end

        # __pattern__ for subclassed Regexp
        if text =~ /^__pattern__: \/(.*)\/([imx]*) \(Regexp\)$/
          source = $1
          flags_str = $2
          advance
          r = build_regexp(source, flags_str)
          @_pending_regexp_replacement = r
          next
        end

        # __begin__, __end__, __exclude_end__ for subclassed Range
        if text == "__begin__:"
          advance
          @_pending_range_begin = parse_value(parent_indent + 2)
          next
        end
        if text == "__end__:"
          advance
          @_pending_range_end = parse_value(parent_indent + 2)
          next
        end
        if text =~ /^__exclude_end__: (.+)$/
          @_pending_range_excl = ($1 == "true")
          advance
          next
        end

        # Instance variable
        if text =~ /^(@\w+): (.+)$/
          ivar = $1
          value_text = $2
          advance
          val = parse_inline_value(value_text)
          obj.instance_variable_set(ivar, val)
        elsif text =~ /^(@\w+):$/
          ivar = $1
          advance
          val = parse_value(current_line&.indent || parent_indent + 2)
          obj.instance_variable_set(ivar, val)
        else
          break
        end
      end
    end

    # --- Inline parsing ---

    def parse_inline_value(text)
      text = text.strip

      # Bare scalars
      return nil if text == "nil"
      return true if text == "true"
      return false if text == "false"

      # Reference
      if text =~ /^\*(\w+)( \(ref\))?$/
        return @registry.resolve($1)
      end

      # Base64 string
      if text =~ /^base64:(\S+) \(String, (.+?), (\d+) bytes\)$/
        return Base64.strict_decode64($1)
      end

      # String with encoding
      if text =~ /^"(.*)" \(String, (.+)\)$/
        return unescape($1).encode($2)
      end

      # String (annotated)
      if text =~ /^"(.*)" \(String\)$/
        return unescape($1)
      end

      # Bare string
      if text =~ /^"(.*)"$/
        return unescape($1)
      end

      # Bare symbol
      if text =~ /^:(.+)$/
        return $1.to_sym
      end

      # Inline Array
      if text =~ /^\[.*\] \(Array\)$/
        return parse_inline_array(text)
      end

      # Inline Hash
      if text =~ /^\{.*\} \(Hash\)$/
        return parse_inline_hash(text)
      end

      # Range (annotated)
      if text =~ /^(.+?)(\.\.\.?)(.+) \(Range\)$/
        range_begin = parse_inline_value($1)
        range_end = parse_inline_value($3)
        return Range.new(range_begin, range_end, $2 == "...")
      end

      # Regexp
      if text =~ /^\/(.*)\/([imx]*) \(Regexp\)$/
        return build_regexp($1, $2)
      end

      # Time with usec
      if text =~ /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.(\d+) ([+-]\d{4}) \(Time\)$/
        return parse_time_with_usec($1, $2, $3)
      end

      # Time
      if text =~ /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}) \(Time\)$/
        return Time.parse($1)
      end

      # Float special
      return Float::INFINITY if text == "Infinity"
      return -Float::INFINITY if text == "-Infinity"
      return Float::NAN if text == "NaN"
      return -0.0 if text == "-0.0"

      # Float
      if text =~ /^-?\d+\.\d+$/ || text =~ /^-?\d+(\.\d+)?e[+-]?\d+$/i
        return text.to_f
      end

      # Integer
      if text =~ /^-?\d+$/
        return text.to_i
      end

      raise "Cannot parse inline value: #{text}"
    end

    def parse_inline_array(text)
      inner = text.sub(/^\[/, "").sub(/\] \(Array\)$/, "")
      return [] if inner.strip.empty?
      elements = split_inline(inner)
      elements.map { |el| parse_inline_value(el) }
    end

    def parse_inline_hash(text)
      inner = text.sub(/^\{/, "").sub(/\} \(Hash\)$/, "")
      return {} if inner.strip.empty?

      hash = {}
      pairs = split_inline(inner)
      pairs.each do |pair|
        if pair =~ /^(\w+): (.+)$/
          key = $1.to_sym
          value = parse_inline_value($2)
          hash[key] = value
        elsif pair =~ /^(.+?) => (.+)$/
          key = parse_inline_value($1)
          value = parse_inline_value($2)
          hash[key] = value
        end
      end
      hash
    end

    def split_inline(str)
      elements = []
      current = ""
      depth = 0
      in_string = false
      escape_next = false

      str.each_char do |ch|
        if escape_next
          current += ch
          escape_next = false
          next
        end

        if ch == "\\"
          current += ch
          escape_next = true
          next
        end

        if ch == '"'
          in_string = !in_string
          current += ch
          next
        end

        if !in_string
          if ch == "[" || ch == "{" || ch == "("
            depth += 1
            current += ch
          elsif ch == "]" || ch == "}" || ch == ")"
            depth -= 1
            current += ch
          elsif ch == "," && depth == 0
            elements << current.strip
            current = ""
          else
            current += ch
          end
        else
          current += ch
        end
      end

      elements << current.strip unless current.strip.empty?
      elements
    end

    def parse_multiline_array(parent_indent)
      arr = []
      parse_multiline_array_into(arr, parent_indent)
      arr
    end

    def parse_multiline_array_into(arr, parent_indent)
      while !eof? && current_line.indent > parent_indent
        arr << parse_value(current_line.indent)
      end
    end

    def parse_multiline_hash(parent_indent)
      hash = {}
      parse_multiline_hash_into(hash, parent_indent)
      hash
    end

    def parse_multiline_hash_into(hash, parent_indent)
      while !eof? && current_line.indent > parent_indent
        line = current_line
        text = line.text

        if text =~ /^(.+?) => (.+)$/
          key = parse_inline_value($1)
          value = parse_inline_value($2)
          advance
          hash[key] = value
        elsif text =~ /^(.+?) =>$/
          key = parse_inline_value($1)
          advance
          value = parse_value(line.indent + 1)
          hash[key] = value
        elsif text == "(entry)"
          # Complex key: (entry) followed by key value, then =>, then value
          advance
          key = parse_value(line.indent + 1)
          # Skip the => line
          if !eof? && current_line.text == "=>"
            advance
          end
          value = parse_value(line.indent + 1)
          hash[key] = value
        else
          break
        end
      end
    end

    def unescape(str)
      result = +""
      i = 0
      while i < str.length
        if str[i] == "\\" && i + 1 < str.length
          case str[i + 1]
          when "n" then result << "\n"; i += 2
          when "r" then result << "\r"; i += 2
          when "t" then result << "\t"; i += 2
          when "0" then result << "\0"; i += 2
          when "\\" then result << "\\"; i += 2
          when '"' then result << '"'; i += 2
          when "x"
            # \xHH hex escape
            if i + 3 < str.length
              hex = str[i + 2, 2]
              result << hex.to_i(16).chr
              i += 4
            else
              result << str[i]; i += 1
            end
          else result << str[i]; i += 1
          end
        else
          result << str[i]
          i += 1
        end
      end
      result
    end

    def resolve_class(name)
      name.split("::").reduce(Object) { |mod, const| mod.const_get(const) }
    rescue NameError
      raise ArgumentError, "undefined class/module #{name}"
    end
  end
end
