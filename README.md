# marshal-md

Human-readable Ruby Marshal alternative. Serializes Ruby objects to Markdown format with full round-trip fidelity.

## Why?

Ruby's `Marshal.dump` produces opaque binary. `marshal-md` produces readable, diff-friendly text while maintaining the same API and behavior.

```
Marshal.dump({name: "Alice", age: 30})
# => "\x04\b{\a:\tname\"\nAlice:\bage\x1Ei\x23"

MarshalMd.dump({name: "Alice", age: 30})
# => {name: "Alice", age: 30} (Hash)
```

## Install

```ruby
gem "marshal-md"
```

## Usage

API is symmetric with Ruby's `Marshal`:

```ruby
require "marshal-md"

# Dump
md = MarshalMd.dump(obj)    # => Markdown string
MarshalMd.dump(obj, io)     # write to IO

# Load
obj = MarshalMd.load(md)    # from string
obj = MarshalMd.load(io)    # from IO
```

## Format

### Scalars

```
42 (Integer)
3.14 (Float)
"hello world" (String)
true (Boolean)
nil (NilClass)
:foo (Symbol)
```

### Collections

```
[1, "two", 3.0] (Array)
{name: "Alice", age: 30} (Hash)
1..10 (Range)
/^\d+$/ (Regexp)
2026-04-03 10:30:00.000000 +0800 (Time)
```

### Objects

```
#<Email> (Email)
  @subject: "URGENT: Server down"
  @body: "Database connection pool exhausted"
  @priority: "high"
```

### Nested structures

```
#<User> (User)
  @name: "Alice"
  @scores: [85, 92, 78] (Array)
  @address:
    #<Address> (Address)
      @city: "Tokyo"
      @zip: "100-0001"
```

### References and circular references

```
&obj_1 [1, 2, 3] (Array)
*obj_1 (ref)
```

Circular:
```
&obj_1 (Array)
  1 (Integer)
  *obj_1 (ref)
```

### Binary data

```
base64:iVBORw0KGgo... (String, ASCII-8BIT, 4096 bytes)
```

## Monkey-patch mode

Drop-in replacement for `Marshal`:

```ruby
require "marshal-md/patch"

Marshal.dump(obj)   # => Markdown (not binary)
Marshal.load(md)    # auto-detects format

# Binary still available
Marshal.binary_dump(obj)
Marshal.binary_load(data)
```

Format detection: binary Marshal starts with `\x04\x08`. Everything else is treated as Markdown.

## Compatibility

Passes the CRuby official `Marshal` test suite (52 tests, 464 assertions).

Supported types:
- All primitives: Integer, Float, String, Symbol, true, false, nil
- Collections: Array, Hash, Range, Regexp, Time, Struct
- Numeric: Complex, Rational
- Custom objects: instance variables, `marshal_dump`/`marshal_load`, `_dump`/`_load`
- Subclassed built-in types
- Module extensions (`extend`, `prepend`)
- Shared and circular references
- Class/Module references

Unsupported (same as `Marshal`):
- Proc / Lambda
- IO / File
- Thread / Fiber
- Binding
- Method / UnboundMethod

## Requirements

- Ruby >= 2.5
- Zero runtime dependencies

## License

MIT
