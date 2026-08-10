defmodule WxMVU.GLCanvas.Draw.Std140Test do
  use ExUnit.Case, async: true

  alias WxMVU.GLCanvas.Draw.Std140

  doctest WxMVU.GLCanvas.Draw.Std140

  describe "layout/1 - scalars" do
    test "packs consecutive scalars tightly and rounds the block to 16" do
      # The spectrogram case.
      layout = Std140.layout(row_offset: :f32, db_min: :f32, db_max: :f32)

      assert Std140.offsets(layout) == %{row_offset: 0, db_min: 4, db_max: 8}
      assert layout.size == 16
    end

    test "a single scalar still occupies a full 16-byte block" do
      assert Std140.layout(x: :f32).size == 16
    end
  end

  describe "layout/1 - vec3 alignment" do
    test "the constellation case: f32 then two vec3s is 48 bytes, not 28" do
      layout = Std140.layout(max_value: :f32, color_low: :vec3, color_high: :vec3)

      assert Std140.offsets(layout) == %{max_value: 0, color_low: 16, color_high: 32}
      assert layout.size == 48
    end

    test "a scalar may follow a vec3 inside the same 16 bytes" do
      layout = Std140.layout(color: :vec3, alpha: :f32)

      assert Std140.offsets(layout) == %{color: 0, alpha: 12}
      assert layout.size == 16
    end

    test "a vec2 may not straddle the vec3 tail" do
      layout = Std140.layout(color: :vec3, offset: :vec2)

      assert Std140.offsets(layout) == %{color: 0, offset: 16}
      assert layout.size == 32
    end
  end

  describe "layout/1 - vec2 alignment" do
    test "vec2 aligns to 8, not 4" do
      layout = Std140.layout(a: :f32, b: :vec2)

      assert Std140.offsets(layout) == %{a: 0, b: 8}
      assert layout.size == 16
    end
  end

  describe "layout/1 - matrices" do
    test "mat3 is 48 bytes because each column is padded to vec4" do
      assert Std140.size(:mat3) == 48
      assert Std140.layout(m: :mat3).size == 48
    end

    test "mat4 is 64 bytes with no interior padding" do
      assert Std140.size(:mat4) == 64
      assert Std140.layout(m: :mat4).size == 64
    end

    test "a scalar after a mat3 starts at 48" do
      layout = Std140.layout(m: :mat3, x: :f32)

      assert Std140.offsets(layout) == %{m: 0, x: 48}
      assert layout.size == 64
    end
  end

  describe "layout/1 - arrays" do
    test "every array element is padded to 16 bytes" do
      # The classic mistake: this is 64 bytes, not 16.
      assert Std140.size({:array, :f32, 4}) == 64
      assert Std140.array_stride(:f32) == 16
    end

    test "vec4 arrays are already tightly packed" do
      assert Std140.size({:array, :vec4, 3}) == 48
    end

    test "mat4 arrays stride by 64" do
      assert Std140.size({:array, :mat4, 2}) == 128
    end
  end

  describe "layout/1 - validation" do
    test "rejects an empty block" do
      assert_raise ArgumentError, ~r/at least one field/, fn -> Std140.layout([]) end
    end

    test "rejects duplicate field names" do
      assert_raise ArgumentError, ~r/duplicate field names/, fn ->
        Std140.layout(a: :f32, a: :vec3)
      end
    end

    test "rejects an unknown type" do
      assert_raise ArgumentError, ~r/unsupported std140 type/, fn ->
        Std140.layout(a: :float64)
      end
    end
  end

  describe "pack/2" do
    test "produces exactly the block size" do
      layout = Std140.layout(max_value: :f32, color_low: :vec3, color_high: :vec3)

      packed =
        Std140.pack(layout, %{
          max_value: 1.0,
          color_low: {0.0, 0.1, 0.2},
          color_high: {1.0, 0.9, 0.8}
        })

      assert byte_size(packed) == layout.size
      assert byte_size(packed) == 48
    end

    test "writes each field at its computed offset" do
      layout = Std140.layout(max_value: :f32, color_low: :vec3, color_high: :vec3)

      packed =
        Std140.pack(layout, %{
          max_value: 2.5,
          color_low: {1.0, 2.0, 3.0},
          color_high: {4.0, 5.0, 6.0}
        })

      assert <<2.5::float-32-native, _pad::binary-size(12), 1.0::float-32-native,
               2.0::float-32-native, 3.0::float-32-native, _pad2::binary-size(4),
               4.0::float-32-native, 5.0::float-32-native, 6.0::float-32-native,
               _tail::binary-size(4)>> = packed
    end

    test "accepts lists as well as tuples for vectors" do
      layout = Std140.layout(color: :vec3)

      assert Std140.pack(layout, %{color: [1.0, 2.0, 3.0]}) ==
               Std140.pack(layout, %{color: {1.0, 2.0, 3.0}})
    end

    test "accepts integers where a float is expected" do
      layout = Std140.layout(x: :f32)
      assert <<1.0::float-32-native, _::binary>> = Std140.pack(layout, %{x: 1})
    end

    test "pads mat3 columns out to 16 bytes each" do
      layout = Std140.layout(m: :mat3)
      packed = Std140.pack(layout, %{m: [1, 2, 3, 4, 5, 6, 7, 8, 9]})

      assert byte_size(packed) == 48

      assert <<1.0::float-32-native, 2.0::float-32-native, 3.0::float-32-native, 0::32,
               4.0::float-32-native, _rest::binary>> = packed
    end

    test "pads array elements out to their stride" do
      layout = Std140.layout(values: {:array, :f32, 3})
      packed = Std140.pack(layout, %{values: [1.0, 2.0, 3.0]})

      assert byte_size(packed) == 48
      assert <<1.0::float-32-native, 0::96, 2.0::float-32-native, _rest::binary>> = packed
    end

    test "refuses to silently zero-fill a missing field" do
      layout = Std140.layout(a: :f32, b: :f32)

      assert_raise ArgumentError, ~r/missing uniform fields: \[:b\]/, fn ->
        Std140.pack(layout, %{a: 1.0})
      end
    end

    test "rejects unknown fields" do
      layout = Std140.layout(a: :f32)

      assert_raise ArgumentError, ~r/unknown uniform fields: \[:typo\]/, fn ->
        Std140.pack(layout, %{a: 1.0, typo: 2.0})
      end
    end

    test "rejects a vector of the wrong arity" do
      layout = Std140.layout(color: :vec3)

      assert_raise ArgumentError, ~r/expects 3 components, got 2/, fn ->
        Std140.pack(layout, %{color: {1.0, 2.0}})
      end
    end
  end

  describe "pack_field/3" do
    test "returns the offset and encoded value for a single field" do
      layout = Std140.layout(max_value: :f32, color_low: :vec3, color_high: :vec3)

      assert {32, encoded} = Std140.pack_field(layout, :color_high, {1.0, 2.0, 3.0})
      assert byte_size(encoded) == 12
    end

    test "raises on an unknown field" do
      layout = Std140.layout(a: :f32)

      assert_raise ArgumentError, ~r/unknown uniform field :nope/, fn ->
        Std140.pack_field(layout, :nope, 1.0)
      end
    end
  end

  describe "reorder_hint/1" do
    test "reports the saving available on the constellation block" do
      layout = Std140.layout(max_value: :f32, color_low: :vec3, color_high: :vec3)

      # vec3, vec3, f32 packs to 32 rather than 48.
      assert {:ok, 16} = Std140.reorder_hint(layout)
    end

    test "reports nothing when the declaration is already optimal" do
      layout = Std140.layout(color_low: :vec3, color_high: :vec3, max_value: :f32)

      assert layout.size == 32
      assert Std140.reorder_hint(layout) == :none
    end
  end
end
