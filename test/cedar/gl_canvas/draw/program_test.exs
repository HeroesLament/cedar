defmodule Cedar.GLCanvas.Draw.ProgramTest do
  use ExUnit.Case, async: true

  # Everything here exercises the compile-time half of the macro. `load/1`
  # needs a current GL context and is covered by running an actual canvas.

  defmodule SpectrogramShader do
    @vertex_shader "#version 410 core\nvoid main() {}\n"
    @fragment_shader "#version 410 core\nvoid main() {}\n"

    use Cedar.GLCanvas.Draw.Program,
      source: {:inline, vert: @vertex_shader, frag: @fragment_shader},
      blocks: [
        per_frame: [
          name: "Uniforms",
          binding: 0,
          fields: [row_offset: :f32, db_min: :f32, db_max: :f32]
        ]
      ],
      samplers: [u_spectrogram: 0, u_colormap: 1],
      vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
  end

  defmodule MultiBlockShader do
    use Cedar.GLCanvas.Draw.Program,
      source: {:inline, vert: "", frag: ""},
      blocks: [
        per_frame: [name: "PerFrame", binding: 0, fields: [view_proj: :mat4]],
        per_object: [name: "PerObject", binding: 1, fields: [model: :mat4, tint: :vec4]]
      ]
  end

  describe "source/0" do
    test "resolves module attributes at the call site" do
      assert {:inline, vert: vert, frag: frag} = SpectrogramShader.source()
      assert vert =~ "#version 410 core"
      assert frag =~ "#version 410 core"
    end
  end

  describe "vertex layout" do
    test "computes stride rather than requiring it by hand" do
      # Two vec2s of f32: this is the hand-written 16 in both canvases today.
      assert SpectrogramShader.stride() == 16
    end

    test "assigns attribute indices in declaration order with computed offsets" do
      assert [position, texcoord] = SpectrogramShader.vertex_layout()

      assert position == %{
               name: :a_position,
               index: 0,
               count: 2,
               type: :float,
               normalized: false,
               offset: 0
             }

      assert texcoord.index == 1
      assert texcoord.offset == 8
    end

    test "defaults to an empty layout when not declared" do
      assert MultiBlockShader.vertex_layout() == []
      assert MultiBlockShader.stride() == 0
    end
  end

  describe "blocks" do
    test "exposes declarations in order" do
      assert [%{key: :per_frame, name: "Uniforms", binding: 0}] = SpectrogramShader.blocks()
    end

    test "computes std140 block sizes" do
      assert SpectrogramShader.block_size(:per_frame) == 16
      assert MultiBlockShader.block_size(:per_frame) == 64
      assert MultiBlockShader.block_size(:per_object) == 80
    end

    test "supports multiple blocks with distinct bindings" do
      assert [%{key: :per_frame, binding: 0}, %{key: :per_object, binding: 1}] =
               MultiBlockShader.blocks()
    end

    test "raises on an unknown block, naming what is declared" do
      assert_raise ArgumentError, ~r/unknown uniform block :nope.*per_frame/s, fn ->
        SpectrogramShader.layout(:nope)
      end
    end
  end

  describe "pack/2" do
    test "packs a declared block to its computed size" do
      packed =
        SpectrogramShader.pack(:per_frame, %{row_offset: 0.5, db_min: -100.0, db_max: 0.0})

      assert byte_size(packed) == 16

      assert <<0.5::float-32-native, -100.0::float-32-native, +0.0::float-32-native, 0::32>> =
               packed
    end

    test "refuses a partial block" do
      assert_raise ArgumentError, ~r/missing uniform fields/, fn ->
        SpectrogramShader.pack(:per_frame, %{row_offset: 0.5})
      end
    end
  end

  describe "samplers/0" do
    test "keeps declared texture units" do
      assert SpectrogramShader.samplers() == [u_spectrogram: 0, u_colormap: 1]
    end

    test "defaults to none" do
      assert MultiBlockShader.samplers() == []
    end
  end

  describe "declaration validation" do
    test "rejects duplicate block bindings" do
      assert_raise ArgumentError, ~r/duplicate block bindings/, fn ->
        defmodule DuplicateBinding do
          use Cedar.GLCanvas.Draw.Program,
            source: {:inline, vert: "", frag: ""},
            blocks: [
              a: [name: "A", binding: 0, fields: [x: :f32]],
              b: [name: "B", binding: 0, fields: [y: :f32]]
            ]
        end
      end
    end

    test "rejects a block missing its binding" do
      assert_raise ArgumentError, ~r/missing :binding/, fn ->
        defmodule MissingBinding do
          use Cedar.GLCanvas.Draw.Program,
            source: {:inline, vert: "", frag: ""},
            blocks: [a: [name: "A", fields: [x: :f32]]]
        end
      end
    end

    test "rejects an unsupported vertex attribute type" do
      assert_raise ArgumentError, ~r/unsupported vertex attribute type/, fn ->
        defmodule BadAttrib do
          use Cedar.GLCanvas.Draw.Program,
            source: {:inline, vert: "", frag: ""},
            vertex_layout: [a: {:f64, 2}]
        end
      end
    end
  end
end
