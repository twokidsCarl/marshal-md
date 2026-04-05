# frozen_string_literal: false
#
# Adapts the official CRuby Marshal test suite for MarshalMd.
# Part 1: marshaltestlib.rb (52 tests) — override encode/decode
# Part 2: test_marshal.rb applicable tests — adapted manually
#

require "test/unit"
require_relative "../lib/marshal-md"
require_relative "marshaltestlib"

# ======================================================================
# Part 1: marshaltestlib.rb — all 52 tests via include
# ======================================================================
class TestMarshalMdLib < Test::Unit::TestCase
  include MarshalTestLib

  def encode(o)
    MarshalMd.dump(o)
  end

  def decode(s)
    MarshalMd.load(s)
  end
end

# ======================================================================
# Part 2: Applicable tests from CRuby test_marshal.rb
# Skipped: tests that depend on binary Marshal format, raw byte manipulation,
#   IO.pipe threading, Marshal.load proc/freeze kwargs, EnvUtil, callcc,
#   or CRuby-internal behaviors (shape, symlink binary encoding, etc.)
# ======================================================================

class C_dump
  def initialize(str)
    @str = str
  end
  attr_reader :str
  def _dump(limit)
    @str
  end
  def self._load(s)
    new(s)
  end
end

class C5_marshal_dump
  def marshal_dump
    "foo"
  end
  def marshal_load(foo)
    @foo = foo
  end
  def initialize(x)
    @x = x
  end
end

class C6_marshal_dump_io
  def initialize
    @stdin = STDIN
  end
  attr_reader :stdin
  def marshal_dump
    1
  end
  def marshal_load(x)
    @stdin = STDIN
  end
end

class LoadData
  attr_reader :data
  def initialize(data)
    @data = data
  end
  alias marshal_dump data
  alias marshal_load initialize
end

TestMarshalMdStruct1 = Struct.new(:foo, :bar)

class TestMarshalMd < Test::Unit::TestCase
  def fact(n)
    return 1 if n == 0
    f = 1
    while n > 0
      f *= n
      n -= 1
    end
    f
  end

  # --- Basic round-trip ---
  def test_marshal
    a = [1, 2, 3, 2**32, 2**64, [4, 5, "foo"], {1 => "bar"}, 2.5, fact(30)]
    assert_equal a, MarshalMd.load(MarshalMd.dump(a))

    [[1, 2, 3, 4], [81, 2, 118, 3146]].each { |w, x, y, z|
      obj = (x.to_f + y.to_f / z.to_f) * Math.exp(w.to_f / (x.to_f + y.to_f / z.to_f))
      assert_equal obj, MarshalMd.load(MarshalMd.dump(obj))
    }

    [1.0, 10.0, 100.0, 110.0].each { |x|
      assert_equal(x, MarshalMd.load(MarshalMd.dump(x)), '[ruby-dev:41936]')
    }
  end

  # --- Integer stress ---
  def test_marshal_integers
    a = []
    [-2, -1, 0, 1, 2].each do |i|
      0.upto(65).map do |exp|
        a << 2**exp + i
      end
    end
    assert_equal a, MarshalMd.load(MarshalMd.dump(a))

    a = [2**32, []] * 2
    assert_equal a, MarshalMd.load(MarshalMd.dump(a))

    a = [2**32, 2**32, []] * 2
    assert_equal a, MarshalMd.load(MarshalMd.dump(a))
  end

  # --- userdef encoding ---
  def test_userdef_encoding
    s1 = "\xa4\xa4".force_encoding("euc-jp")
    o1 = C_dump.new(s1)
    m = MarshalMd.dump(o1)
    o2 = MarshalMd.load(m)
    s2 = o2.str
    assert_equal(s1, s2)
  end

  # --- userdef invalid ---
  def test_userdef_invalid
    o = C_dump.new(nil)
    assert_raise(TypeError) { MarshalMd.dump(o) }
  end

  # --- Class/Module ---
  def test_class
    o = class << Object.new; self; end
    assert_raise(TypeError) { MarshalMd.dump(o) }
    assert_equal(Object, MarshalMd.load(MarshalMd.dump(Object)))
    assert_equal(Enumerable, MarshalMd.load(MarshalMd.dump(Enumerable)))
  end

  # --- Symbol ---
  def test_symbol2
    [:ruby].each do |sym|
      assert_equal(sym, MarshalMd.load(MarshalMd.dump(sym)), '[ruby-core:24788]')
    end
    bug2548 = '[ruby-core:27375]'
    ary = [:$1, nil]
    assert_equal(ary, MarshalMd.load(MarshalMd.dump(ary)), bug2548)
  end

  # --- marshal_dump protocol ---
  def test_marshal_dump
    c = C5_marshal_dump.new("bar")
    s = MarshalMd.dump(c)
    d = MarshalMd.load(s)
    assert_equal("foo", d.instance_variable_get(:@foo))
    assert_equal(false, d.instance_variable_defined?(:@x))
  end

  # --- marshal_dump with IO ivar ---
  def test_marshal_dump_extra_iv
    o = C6_marshal_dump_io.new
    m = nil
    assert_nothing_raised("[ruby-dev:21475] [ruby-dev:39845]") {
      m = MarshalMd.dump(o)
    }
    o2 = MarshalMd.load(m)
    assert_equal(STDIN, o2.stdin)
  end

  # --- String encoding round-trip ---
  def test_marshal_string_encoding
    o1 = ["foo".force_encoding("EUC-JP")] + ["bar"] * 2
    m = MarshalMd.dump(o1)
    o2 = MarshalMd.load(m)
    assert_equal(o1, o2, "[ruby-dev:40388]")
  end

  # --- Encoding object ---
  def test_marshal_encoding_encoding
    # Encoding objects use CRuby-internal marshal format (type 'e')
    # that has no public API equivalent. MarshalMd treats them as
    # regular objects. This is a known divergence from Marshal.
    # Verify it doesn't crash.
    o1 = Encoding.find("EUC-JP")
    assert_nothing_raised { MarshalMd.dump(o1) }
  end

  # --- Flonum reference ---
  def test_marshal_flonum_reference
    bug7348 = '[ruby-core:49323]'
    e = []
    ary = [[2.0, e], [e]]
    assert_equal(ary, MarshalMd.load(MarshalMd.dump(ary)), bug7348)
  end

  # --- Complex ---
  def test_marshal_complex
    assert_equal(Complex(1, 2), MarshalMd.load(MarshalMd.dump(Complex(1, 2))))
  end

  # --- Rational ---
  def test_marshal_rational
    assert_equal(Rational(1, 2), MarshalMd.load(MarshalMd.dump(Rational(1, 2))))
  end

  # --- Struct with marshal_dump ---
  class Bug7627 < Struct.new(:bar)
    attr_accessor :foo
    def marshal_dump; 'dump'; end
    def marshal_load(*); end
  end

  def test_marshal_dump_struct_ivar
    bug7627 = '[ruby-core:51163]'
    obj = Bug7627.new
    obj.foo = '[Bug #7627]'
    dump = MarshalMd.dump(obj)
    loaded = MarshalMd.load(dump)
    assert_equal(obj, loaded, bug7627)
    assert_nil(loaded.foo, bug7627)
  end

  # --- Exception ---
  def test_marshal_exception
    begin
      raise "test error"
    rescue => e
      e2 = MarshalMd.load(MarshalMd.dump(e))
      assert_equal(e.message, e2.message)
      assert_equal(e.backtrace, e2.backtrace)
    end
  end

  # --- NameError ---
  def test_marshal_nameerror
    begin
      eval("unknown_method_xyz")
    rescue NameError => e
      e2 = MarshalMd.load(MarshalMd.dump(e))
      assert_equal(e.message.lines.first.chomp, e2.message.lines.first.chomp)
      assert_equal(e.backtrace, e2.backtrace)
    end
  end

  # --- respond_to? arity ---
  class TestForRespondToFalse
    def respond_to?(a, priv = false)
      false
    end
  end

  def test_marshal_respond_to_arity
    assert_nothing_raised(ArgumentError, '[Bug #7722]') do
      MarshalMd.dump(TestForRespondToFalse.new)
    end
  end

  # --- Struct keyword_init ---
  def test_marshal_keyword_init_struct
    s = Struct.new(:foo, keyword_init: true)
    # Anonymous struct — can't round-trip (no class name)
    assert_raise(TypeError) { MarshalMd.dump(s.new(foo: 42)) }
  end

  # --- Named Struct round-trip ---
  def test_marshal_named_struct
    obj = TestMarshalMdStruct1.new("hello", 42)
    obj2 = MarshalMd.load(MarshalMd.dump(obj))
    assert_equal(obj, obj2)
    assert_equal("hello", obj2.foo)
    assert_equal(42, obj2.bar)
  end

  # --- Private class ---
  class PrivateClass
    def initialize(foo)
      @foo = foo
    end
    attr_reader :foo
  end

  def test_marshal_private_class
    o1 = PrivateClass.new("test")
    o2 = MarshalMd.load(MarshalMd.dump(o1))
    assert_equal(o1.class, o2.class)
    assert_equal(o1.foo, o2.foo)
  end

  # --- Undumpable types ---
  def test_undumpable_proc
    assert_raise(TypeError) { MarshalMd.dump(proc {}) }
    assert_raise(TypeError) { MarshalMd.dump(-> {}) }
  end

  def test_undumpable_io
    assert_raise(TypeError) { MarshalMd.dump($stdout) }
  end

  def test_undumpable_method
    assert_raise(TypeError) { MarshalMd.dump(method(:puts)) }
    assert_raise(TypeError) { MarshalMd.dump(String.instance_method(:length)) }
  end

  def test_undumpable_binding
    assert_raise(TypeError) { MarshalMd.dump(binding) }
  end

  def test_undumpable_thread
    t = Thread.new { sleep 100 }
    assert_raise(TypeError) { MarshalMd.dump(t) }
    t.kill
  end

  def test_undumpable_anonymous
    c = Class.new
    assert_raise(TypeError) { MarshalMd.dump(c) }
    o = c.new
    assert_raise(TypeError) { MarshalMd.dump(o) }
    m = Module.new
    assert_raise(TypeError) { MarshalMd.dump(m) }
  end

  def test_undumpable_singleton
    o = Object.new
    def o.m() end
    assert_raise(TypeError) { MarshalMd.dump(o) }
  end

  def test_undumpable_hash_default_proc
    h = Hash.new {}
    assert_raise(TypeError) { MarshalMd.dump(h) }
  end

  # --- Packed string (binary) ---
  def test_packed_string
    packed = ["foo"].pack("p")
    bare = "".force_encoding(Encoding::ASCII_8BIT) << packed
    # Both should produce the same dump (base64 encoded)
    assert_equal(MarshalMd.dump(bare), MarshalMd.dump(packed))
  end

  # --- LoadData with marshal_dump/marshal_load ---
  def test_load_data_round_trip
    t = LoadData.new("hello")
    s = MarshalMd.dump(t)
    t2 = MarshalMd.load(s)
    assert_equal(t.data, t2.data)
  end

  # --- Negative zero ---
  def test_negative_zero
    nz = -0.0
    result = MarshalMd.load(MarshalMd.dump(nz))
    assert_equal(-Float::INFINITY, 1.0 / result)
  end

  # --- Large nested structure ---
  def test_deep_nesting
    obj = [1]
    20.times { obj = [obj] }
    assert_equal(obj, MarshalMd.load(MarshalMd.dump(obj)))
  end

  # --- Hash with various key types ---
  def test_hash_various_keys
    h = { 1 => "int", "str" => "string", :sym => "symbol", [1] => "array" }
    h2 = MarshalMd.load(MarshalMd.dump(h))
    assert_equal(h, h2)
  end

  # --- Empty containers ---
  def test_empty_containers
    assert_equal([], MarshalMd.load(MarshalMd.dump([])))
    assert_equal({}, MarshalMd.load(MarshalMd.dump({})))
    assert_equal("", MarshalMd.load(MarshalMd.dump("")))
  end

  # --- IO support ---
  def test_dump_to_io
    require "stringio"
    io = StringIO.new
    MarshalMd.dump([1, 2, 3], io)
    io.rewind
    assert_equal([1, 2, 3], MarshalMd.load(io))
  end

  # --- Depth limit ---
  def test_limit
    assert_equal([[[]]], MarshalMd.load(MarshalMd.dump([[[]]], 3)))
    assert_raise(ArgumentError) { MarshalMd.dump([[[]]], 2) }
    # Strings are leaf values — should not count against depth
    assert_nothing_raised(ArgumentError, '[ruby-core:24100]') { MarshalMd.dump("\u3042", 1) }
  end

  def test_limit_io
    require "stringio"
    io = StringIO.new
    MarshalMd.dump([1, 2], io, 2)
    io.rewind
    assert_equal([1, 2], MarshalMd.load(io))
  end

  # --- Pipe IO ---
  def test_pipe
    o1 = C_dump.new("a" * 10000)
    IO.pipe do |r, w|
      th = Thread.new { MarshalMd.dump(o1, w); w.close }
      o2 = MarshalMd.load(r)
      th.join
      assert_equal(o1.str, o2.str)
    end
  end

  # --- Freeze mode ---
  def test_freeze
    source = ["foo", {}, 1..2]
    objects = MarshalMd.load(MarshalMd.dump(source), freeze: true)
    assert_equal(source, objects)
    assert_predicate(objects, :frozen?)
    objects.each do |obj|
      assert_predicate(obj, :frozen?)
    end
  end

  # --- Proc callback ---
  def test_proc_callback
    str = "x"
    obj = [str, str]
    result = MarshalMd.load(MarshalMd.dump(obj), ->(v) { v == str ? v.upcase : v })
    assert_equal(["X", "X"], result)
  end

  def test_proc_freeze
    object = { foo: [42, "bar"] }
    assert_equal(object, MarshalMd.load(MarshalMd.dump(object), :freeze.to_proc))
  end

  # --- Proc with shared references (honor post_proc value for link) ---
  def test_proc_shared_ref_replacement
    str = 'x'
    obj = [str, str]
    result = MarshalMd.load(MarshalMd.dump(obj), ->(v) { v == str ? v.upcase : v })
    assert_equal(['X', 'X'], result)
  end

  # --- Hash#compare_by_identity ---
  def test_hash_compared_by_identity
    h = Hash.new
    h.compare_by_identity
    h["a" + "0"] = 1
    h["a" + "0"] = 2
    h2 = MarshalMd.load(MarshalMd.dump(h))
    assert_predicate(h2, :compare_by_identity?)
    a = h2.to_a
    assert_equal([["a0", 1], ["a0", 2]], a.sort)
    assert_not_same(a[1][0], a[0][0])
  end

  def test_hash_default_compared_by_identity
    h = Hash.new(true)
    h.compare_by_identity
    h["a" + "0"] = 1
    h["a" + "0"] = 2
    h2 = MarshalMd.load(MarshalMd.dump(h))
    assert_predicate(h2, :compare_by_identity?)
    a = h2.to_a
    assert_equal([["a0", 1], ["a0", 2]], a.sort)
  end

  # --- Encoding object round-trip ---
  def test_encoding_object
    o1 = [Encoding.find("EUC-JP")] + ["r2"] * 2
    m = MarshalMd.dump(o1)
    o2 = MarshalMd.load(m)
    assert_equal(o1, o2)
  end

  # --- Recursive marshal_dump detection ---
  class RecursiveMarshalDump
    def marshal_dump
      dup
    end
  end

  def test_marshal_dump_recursion
    e = assert_raise(RuntimeError) do
      MarshalMd.dump(RecursiveMarshalDump.new)
    end
    assert_match(/same class instance/, e.message)
  end

  # --- Array modification during dump ---
  class ArrayModifier
    def initialize(ary)
      @ary = ary
    end
    def _dump(s)
      @ary.clear
      "foo"
    end
    def self._load(s)
      new([])
    end
  end

  def test_modify_array_during_dump
    a = []
    o = ArrayModifier.new(a)
    a << o << nil
    assert_raise(RuntimeError) { MarshalMd.dump(a) }
  end

  # --- Ivar modification during dump ---
  class IvarAdder
    attr_accessor :bar, :baz

    def initialize
      self.bar = IvarAdderBar.new(self)
    end

    class IvarAdderBar
      attr_accessor :foo

      def initialize(foo)
        self.foo = foo
      end

      def marshal_dump
        if self.foo.baz
          self.foo.remove_instance_variable(:@baz)
        else
          self.foo.baz = :problem
        end
        {foo: self.foo}
      end

      def marshal_load(data)
        self.foo = data[:foo]
      end
    end
  end

  def test_marshal_dump_adding_instance_variable
    obj = IvarAdder.new
    e = assert_raise(RuntimeError) { MarshalMd.dump(obj) }
    assert_match(/instance variable added/, e.message)
  end

  def test_marshal_dump_removing_instance_variable
    obj = IvarAdder.new
    obj.baz = :test
    e = assert_raise(RuntimeError) { MarshalMd.dump(obj) }
    assert_match(/instance variable removed/, e.message)
  end
end
