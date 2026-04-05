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
MarshalMd.dump(obj, 3)      # with depth limit

# Load
obj = MarshalMd.load(md)                    # from string
obj = MarshalMd.load(io)                    # from IO
obj = MarshalMd.load(md, proc)              # with proc callback
obj = MarshalMd.load(md, freeze: true)      # freeze all objects
```

## Format

### Scalars

No type annotations needed — type is inferred from syntax:

```
42
3.14
"hello world"
true
nil
:foo
```

### Collections

```
[1, "two", 3.0] (Array)
{name: "Alice", age: 30} (Hash)
1..10 (Range)
/^\d+$/ (Regexp)
2026-04-03 10:30:00.000000000 +0800 (Time)
(1+2i) (Complex)
1/3 (Rational)
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
  1
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

Passes the CRuby official `Marshal` test suite (101 tests, 550 assertions) plus 108 RSpec examples.

Supported types:
- All primitives: Integer, Float, String, Symbol, true, false, nil
- Collections: Array, Hash, Range, Regexp, Time, Struct
- Numeric: Complex, Rational
- References: Encoding, Class, Module
- Custom objects: instance variables, `marshal_dump`/`marshal_load`, `_dump`/`_load`
- Subclassed built-in types (MyArray < Array, MyTime < Time, etc.)
- Module extensions (`extend`, `prepend`)
- Shared and circular references
- Exception serialization (message + backtrace)
- `Hash#compare_by_identity`
- Hash with default values

Marshal API features:
- Depth limit: `dump(obj, limit)`
- IO output: `dump(obj, io)`
- Pipe IO: `dump(obj, w)` / `load(r)`
- Proc callback: `load(data, proc)`
- Freeze mode: `load(data, freeze: true)`

Safety checks (same as Marshal):
- Recursive `marshal_dump` detection
- Array modification during dump detection
- Instance variable modification during dump detection
- TypeError for undumpable types (Proc, IO, Thread, Binding, Method, anonymous classes, singletons)

Unsupported (same as `Marshal`):
- Proc / Lambda
- IO / File
- Thread / Fiber
- Binding
- Method / UnboundMethod
- `ruby2_keywords` hash flag (CRuby C-internal, no public Ruby API)

## Requirements

- Ruby >= 2.5
- Zero runtime dependencies

## License

MIT
