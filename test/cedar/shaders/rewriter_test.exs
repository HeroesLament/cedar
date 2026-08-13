defmodule Cedar.Shaders.RewriterTest do
  use ExUnit.Case, async: true

  alias Cedar.Shaders.Rewriter

  # Trimmed from real naga output for the :image shader. The VertexOutput struct
  # is kept deliberately: it also has `member` and `member_1` fields, and is the
  # reason field renames must be scoped rather than global.
  @frag """
  #version 410 core
  struct type_5 {
      float member;
      float member_1;
      float member_2;
  };
  struct type_6 {
      type_5 member;
  };
  struct VertexOutput {
      vec4 member;
      vec2 member_1;
  };
  vec2 v_texcoord_1 = vec2(0.0);

  layout(std140) uniform type_6_block_0Fragment { type_6 _group_0_binding_0_fs; };

  uniform sampler2D _group_0_binding_1_fs;

  uniform sampler2D _group_0_binding_3_fs;

  void function() {
      vec2 _e17 = v_texcoord_1;
      float _e22 = _group_0_binding_0_fs.member.member;
      vec4 _e27 = texture(_group_0_binding_1_fs, vec2(_e17.x, _e22));
      float _e31 = _group_0_binding_0_fs.member.member_1;
      float _e34 = _group_0_binding_0_fs.member.member_2;
      vec4 _e46 = texture(_group_0_binding_3_fs, vec2(_e34, 0.5));
      return;
  }
  """

  @vert """
  #version 410 core
  struct type_5 {
      float member;
      float member_1;
      float member_2;
  };
  struct type_6 {
      type_5 member;
  };
  struct VertexOutput {
      vec4 member;
      vec2 member_1;
  };
  layout(location = 0) in vec2 _p2vs_location0;
  void main() {
      VertexOutput _tmp_return = VertexOutput(vec4(0.0), vec2(0.0));
      gl_Position = _tmp_return.member;
  }
  """

  @shader_spec %{
          block: %{name: "Uniforms", fields: [:row_offset, :domain_min, :domain_max]},
          samplers: %{1 => "u_data", 3 => "u_colormap"}
        }

  describe "derive/2" do
    test "finds the block, structs, fields and samplers" do
      assert {:ok, mapping} = Rewriter.derive(@frag, @shader_spec)

      assert mapping.block == {"type_6_block_0Fragment", "Uniforms"}
      assert mapping.outer_type == {"type_6", "UniformsBlock"}
      assert mapping.inner_type == {"type_5", "UniformsData"}
      assert mapping.instance == {"_group_0_binding_0_fs", "u"}
      assert mapping.wrapper_field == {"member", "data"}

      assert mapping.fields == [
               {"member", "row_offset"},
               {"member_1", "domain_min"},
               {"member_2", "domain_max"}
             ]

      assert mapping.samplers == [
               {"_group_0_binding_1_fs", "u_data"},
               {"_group_0_binding_3_fs", "u_colormap"}
             ]
    end

    test "fails loudly when the declared field count does not match" do
      spec = put_in(@shader_spec.block.fields, [:row_offset, :domain_min])
      assert {:error, message} = Rewriter.derive(@frag, spec)
      assert message =~ "3 fields in the generated GLSL"
      assert message =~ "2 were declared"
      assert message =~ "diverged"
    end

    test "fails when a sampler binding has no declared name" do
      spec = put_in(@shader_spec.samplers, %{1 => "u_data"})
      assert {:error, message} = Rewriter.derive(@frag, spec)
      assert message =~ "bindings 3"
      assert message =~ "merges each texture/sampler pair"
    end

    test "fails when there is no uniform block at all" do
      assert {:error, message} = Rewriter.derive("#version 410 core\nvoid main() {}\n", @shader_spec)
      assert message =~ "no std140 uniform block"
    end
  end

  describe "apply_mapping/2 on the fragment stage" do
    setup do
      {:ok, mapping} = Rewriter.derive(@frag, @shader_spec)
      %{out: Rewriter.apply_mapping(@frag, mapping)}
    end

    test "renames the block, which is the runtime lookup key", %{out: out} do
      assert out =~ "layout(std140) uniform Uniforms { UniformsBlock u; }"
      refute out =~ "type_6_block_0Fragment"
    end

    test "renames the samplers", %{out: out} do
      assert out =~ "uniform sampler2D u_data;"
      assert out =~ "uniform sampler2D u_colormap;"
      refute out =~ "_group_0_binding_1_fs"
      refute out =~ "_group_0_binding_3_fs"
    end

    test "renames struct types", %{out: out} do
      assert out =~ "struct UniformsData {"
      assert out =~ "struct UniformsBlock {"
      refute out =~ ~r/\btype_5\b/
      refute out =~ ~r/\btype_6\b/
    end

    test "renames the uniform fields in their declaration", %{out: out} do
      assert out =~ "float row_offset;"
      assert out =~ "float domain_min;"
      assert out =~ "float domain_max;"
    end

    test "renames the field access chains", %{out: out} do
      assert out =~ "u.data.row_offset"
      assert out =~ "u.data.domain_min"
      assert out =~ "u.data.domain_max"
    end

    test "leaves VertexOutput alone - it has colliding field names", %{out: out} do
      assert out =~ "struct VertexOutput {\n    vec4 member;\n    vec2 member_1;\n};"
    end

    test "no generated identifiers survive anywhere", %{out: out} do
      refute out =~ "_group_0_binding"
      refute out =~ "block_0Fragment"
    end
  end

  describe "apply_mapping/2 on the vertex stage" do
    setup do
      {:ok, mapping} = Rewriter.derive(@frag, @shader_spec)
      %{out: Rewriter.apply_mapping(@vert, mapping)}
    end

    test "renames the carried-over struct declarations", %{out: out} do
      assert out =~ "struct UniformsData {"
      assert out =~ "struct UniformsBlock {"
    end

    test "still leaves VertexOutput and its usage intact", %{out: out} do
      assert out =~ "struct VertexOutput {\n    vec4 member;\n    vec2 member_1;\n};"
      assert out =~ "_tmp_return.member;"
    end
  end

  # A vertex stage that references the block itself. naga names the block per
  # stage, so this file's block and instance differ from the fragment's even
  # though they are the same block in the same program.
  @vert_with_uniforms """
  #version 410 core
  struct type_4 {
      vec4 member;
      vec2 member_1;
      float member_2;
  };
  struct type_5 {
      type_4 member;
  };
  layout(std140) uniform type_5_block_0Vertex { type_5 _group_0_binding_0_vs; };
  void main() {
      vec4 c = _group_0_binding_0_vs.member.member;
      float w = _group_0_binding_0_vs.member.member_2;
  }
  """

  @frag_with_uniforms """
  #version 410 core
  struct type_4 {
      vec4 member;
      vec2 member_1;
      float member_2;
  };
  struct type_5 {
      type_4 member;
  };
  layout(std140) uniform type_5_block_0Fragment { type_5 _group_0_binding_0_fs; };
  void main() {
      vec4 c = _group_0_binding_0_fs.member.member;
  }
  """

  @line_spec %{
    block: %{name: "LineUniforms", fields: [:color, :viewport, :line_width]},
    samplers: %{}
  }

  describe "rewrite_pair/3 with a block referenced from both stages" do
    setup do
      {:ok, out, _mapping} =
        Rewriter.rewrite_pair(@vert_with_uniforms, @frag_with_uniforms, @line_spec)

      out
    end

    test "renames the block in the vertex stage too", %{vert: vert} do
      assert vert =~ "uniform LineUniforms { LineUniformsBlock u; }"
      refute vert =~ "type_5_block_0Vertex"
      refute vert =~ "_group_0_binding_0_vs"
    end

    test "both stages name the block identically, so they link as one", %{
      vert: vert,
      frag: frag
    } do
      extract = fn glsl ->
        [name] =
          Regex.run(~r/uniform\s+(\w+)\s*\{/, glsl, capture: :all_but_first)

        name
      end

      assert extract.(vert) == extract.(frag)
      assert extract.(vert) == "LineUniforms"
    end

    test "renames field accesses in the vertex stage", %{vert: vert} do
      assert vert =~ "u.data.color"
      assert vert =~ "u.data.line_width"
    end

    test "handles an empty sampler map", %{frag: frag} do
      refute frag =~ "sampler"
    end
  end

  describe "rewrite_pair/3" do
    test "derives from the fragment stage and applies to both" do
      assert {:ok, %{vert: vert, frag: frag}, mapping} =
               Rewriter.rewrite_pair(@vert, @frag, @shader_spec)

      assert frag =~ "uniform Uniforms"
      assert vert =~ "struct UniformsData"
      assert mapping.block == {"type_6_block_0Fragment", "Uniforms"}
    end

    test "propagates a derivation failure" do
      spec = put_in(@shader_spec.block.fields, [:only_one])
      assert {:error, message} = Rewriter.rewrite_pair(@vert, @frag, spec)
      assert message =~ "diverged"
    end
  end

  describe "idempotence" do
    test "rewriting already-rewritten output is a no-op for the block name" do
      {:ok, mapping} = Rewriter.derive(@frag, @shader_spec)
      once = Rewriter.apply_mapping(@frag, mapping)

      # Deriving again against the renamed source should now find the clean
      # names, and renaming them to themselves changes nothing.
      assert {:ok, second} = Rewriter.derive(once, @shader_spec)
      assert second.block == {"Uniforms", "Uniforms"}
      assert Rewriter.apply_mapping(once, second) == once
    end
  end
end
