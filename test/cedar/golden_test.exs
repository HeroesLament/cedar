defmodule Cedar.GoldenTest do
  @moduledoc """
  Renders every shipped shader and checks the pixels that come back.

  Excluded by default, because they need a real OpenGL 4.1 core context and a
  display. Run them explicitly:

      mix test --only gl

  These are the layer that catches what nothing else can. Host-side tests cover
  the maths, `mix cedar.shaders.build --check` covers artifact drift, and
  `scripts/verify_shaders.exs` covers whether the GLSL compiles on the local
  driver — but all three pass happily for a shader that links and draws the
  wrong thing. Several bugs on this branch were only ever visible here: a 1px
  gridline that rendered as nothing, and a uniform block renamed in one stage
  but not the other, which would have silently starved the vertex stage of its
  uniforms.

  `async: false` throughout: there is one GL context, and it is made current
  per test process.
  """

  use Cedar.GLCase

  # ==========================================================================
  # Shader declarations
  # ==========================================================================

  defmodule ImageShader do
    use Cedar.GLCanvas.Draw.Program,
      source: {:priv, :cedar, "shaders/image"},
      blocks: [
        per_frame: [
          name: "Uniforms",
          binding: 0,
          fields: [row_offset: :f32, domain_min: :f32, domain_max: :f32]
        ]
      ],
      samplers: [u_data: 0, u_colormap: 1],
      vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
  end

  defmodule LineShader do
    use Cedar.GLCanvas.Draw.Program,
      source: {:priv, :cedar, "shaders/line"},
      blocks: [
        per_frame: [
          name: "LineUniforms",
          binding: 0,
          fields: [color: :vec4, viewport: :vec2, line_width: :f32]
        ]
      ],
      samplers: [],
      vertex_layout: [
        a_position: {:f32, 2},
        a_neighbor: {:f32, 2},
        a_side: {:f32, 1}
      ]
  end

  defmodule GridShader do
    use Cedar.GLCanvas.Draw.Program,
      source: {:priv, :cedar, "shaders/grid"},
      blocks: [
        per_frame: [
          name: "GridUniforms",
          binding: 0,
          fields: [
            line_color: :vec4,
            background: :vec4,
            spacing: :vec2,
            thickness: :f32
          ]
        ]
      ],
      samplers: [],
      vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
  end

  defmodule MeshShader do
    use Cedar.GLCanvas.Draw.Program,
      source: {:priv, :cedar, "shaders/mesh"},
      blocks: [
        per_frame: [
          name: "MeshUniforms",
          binding: 0,
          fields: [
            mvp: :mat4,
            normal_matrix: :mat3,
            light_direction: :vec3,
            base_color: :vec4
          ]
        ]
      ],
      samplers: [],
      vertex_layout: [a_position: {:f32, 3}, a_normal: {:f32, 3}]
  end

  # ==========================================================================
  # :image
  # ==========================================================================

  describe ":image" do
    setup do
      size = 2
      fbo = offscreen(size)

      data = GL.create_texture()
      GL.bind_texture(:texture_2d, data)
      # Row 0 sits at the bottom in texture space.
      GL.tex_image_2d(1, 2, :r32f, :red, :float, floats([-100.0, 0.0]))
      GL.tex_parameter(:min_filter, :nearest)
      GL.tex_parameter(:mag_filter, :nearest)
      GL.tex_parameter(:wrap_s, :clamp_to_edge)
      GL.tex_parameter(:wrap_t, :repeat)

      # 256x1 ramp: pure red at 0.0, pure blue at 1.0.
      colormap_data = for i <- 0..255, into: <<>>, do: <<255 - i::8, 0::8, i::8>>
      colormap = GL.create_texture()
      GL.bind_texture(:texture_2d, colormap)
      GL.tex_image_2d(256, 1, :rgb8, :rgb, :unsigned_byte, colormap_data)
      GL.tex_parameter(:min_filter, :nearest)
      GL.tex_parameter(:mag_filter, :nearest)
      GL.tex_parameter(:wrap_s, :clamp_to_edge)
      GL.tex_parameter(:wrap_t, :clamp_to_edge)

      {vao, _vbo} = buffer(quad_vertices())
      {:ok, program} = ImageShader.load()
      Program.configure_vertex_attribs(program)

      render = fn row_offset ->
        GL.bind_framebuffer(:both, fbo)
        GL.viewport(0, 0, size, size)
        clear()

        Program.bind(program)

        Program.set_block(program, :per_frame, %{
          row_offset: row_offset,
          domain_min: -100.0,
          domain_max: 0.0
        })

        GL.active_texture(0)
        GL.bind_texture(:texture_2d, data)
        GL.active_texture(1)
        GL.bind_texture(:texture_2d, colormap)

        GL.bind_vertex_array(vao)
        GL.draw_arrays(:triangle_strip, 0, 4)
        GL.assert_no_error!()

        # The quad covers the whole framebuffer, so both columns are
        # identical; sample column 0 of the bottom and top rows.
        {pixel(size, 0, 0), pixel(size, 0, 1)}
      end

      %{render: render}
    end

    test "is not vertically flipped", %{render: render} do
      # naga emits two Y negations which should cancel. Data row 0 is -100,
      # which maps to the low end of the colormap - red - and row 0 is the
      # bottom of the texture, so red belongs at the bottom.
      assert {{255, 0, 0}, {0, 0, 255}} = render.(0.0)
    end

    test "scrolls by row_offset", %{render: render} do
      assert {{0, 0, 255}, {255, 0, 0}} = render.(0.5)
    end

    test "wraps a negative offset the same as a positive one", %{render: render} do
      # Rust's .fract() truncates and would sample at a negative coordinate;
      # cedar_shader_core.wrap_unit is floor-based. Scrolling back half a
      # texture must look like scrolling forward half a texture.
      assert render.(-0.5) == render.(0.5)
    end
  end

  # ==========================================================================
  # :line
  # ==========================================================================

  describe ":line" do
    setup do
      size = 16
      fbo = offscreen(size)

      # One horizontal segment. a_neighbor must give the same direction at both
      # ends, or the perpendicular flips and the quad becomes a bowtie.
      {vao, _vbo} =
        buffer(
          floats([
            -0.8, 0.0, 0.8, 0.0, 1.0,
            -0.8, 0.0, 0.8, 0.0, -1.0,
            0.8, 0.0, 2.4, 0.0, 1.0,
            0.8, 0.0, 2.4, 0.0, -1.0
          ])
        )

      {:ok, program} = LineShader.load()
      Program.configure_vertex_attribs(program)

      covered_rows = fn line_width ->
        GL.bind_framebuffer(:both, fbo)
        GL.viewport(0, 0, size, size)
        clear()

        Program.bind(program)

        Program.set_block(program, :per_frame, %{
          color: {1.0, 0.0, 0.0, 1.0},
          viewport: {size * 1.0, size * 1.0},
          line_width: line_width
        })

        GL.bind_vertex_array(vao)
        GL.draw_arrays(:triangle_strip, 0, 4)
        GL.assert_no_error!()

        Enum.count(0..(size - 1), fn row -> elem(pixel(size, div(size, 2), row), 0) == 255 end)
      end

      %{covered_rows: covered_rows, size: size}
    end

    test "expands to exactly the requested pixel width", %{covered_rows: covered_rows} do
      assert covered_rows.(4.0) == 4
      assert covered_rows.(8.0) == 8
      assert covered_rows.(2.0) == 2
    end

    test "the uniform block reaches the vertex stage", %{covered_rows: covered_rows} do
      # naga names a uniform block per stage. If the rewriter renamed only the
      # fragment's, GLSL would see two blocks, the vertex stage would receive
      # no data, line_width would read zero, and the frame would be empty -
      # with no error anywhere.
      assert covered_rows.(2.0) > 0
      assert covered_rows.(8.0) > covered_rows.(2.0)
    end
  end

  # ==========================================================================
  # :grid
  # ==========================================================================

  describe ":grid" do
    setup do
      size = 32
      fbo = offscreen(size)
      {vao, _vbo} = buffer(quad_vertices())

      {:ok, program} = GridShader.load()
      Program.configure_vertex_attribs(program)

      render = fn thickness ->
        GL.bind_framebuffer(:both, fbo)
        GL.viewport(0, 0, size, size)
        clear()

        Program.bind(program)

        Program.set_block(program, :per_frame, %{
          line_color: {1.0, 0.0, 0.0, 1.0},
          background: {0.0, 0.0, 1.0, 1.0},
          spacing: {0.25, 0.25},
          thickness: thickness
        })

        GL.bind_vertex_array(vao)
        GL.draw_arrays(:triangle_strip, 0, 4)
        GL.assert_no_error!()

        red_channel(size)
      end

      %{render: render, size: size}
    end

    test "draws lines and background, not a fill", %{render: render, size: size} do
      reds = render.(2.0)
      total = size * size

      lit = Enum.count(reds, &(&1 > 32))
      background = Enum.count(reds, &(&1 <= 8))

      assert lit > 0, "nothing lit - fwidth may be reading too large"
      assert background > 0, "no background - fwidth may be reading zero"
      assert lit < div(total, 2), "more than half the frame is lit"
    end

    test "antialiases, which means fwidth survived the transpile", %{render: render} do
      # Checked at 1px. A 2px band centred on a pixel boundary box-filters to
      # exactly full coverage on both neighbours, correctly producing no
      # intermediate values at all.
      partial = Enum.count(render.(1.0), &(&1 > 8 and &1 < 250))
      assert partial > 0, "no partial coverage; fwidth is not producing a gradient"
    end

    test "a hairline stays visible", %{render: render} do
      # Gridlines land on integer coordinates, which fall on pixel boundaries.
      # A naive linear falloff evaluates to exactly zero on both neighbours and
      # the line disappears entirely - which it did, before the box filter.
      assert Enum.max(render.(1.0)) > 64
    end

    test "thickness changes coverage", %{render: render} do
      thin = render.(1.0)
      thick = render.(4.0)

      assert Enum.count(thick, &(&1 > 32)) > Enum.count(thin, &(&1 > 32))
      assert Enum.max(thick) > Enum.max(thin)
    end
  end

  # ==========================================================================
  # :mesh
  # ==========================================================================

  describe ":mesh" do
    setup do
      size = 16
      fbo = offscreen(size)

      # A quad over the LEFT half, normals along +X.
      {vao, _vbo} =
        buffer(
          floats([
            -1.0, -1.0, 0.0, 1.0, 0.0, 0.0,
            0.0, -1.0, 0.0, 1.0, 0.0, 0.0,
            -1.0, 1.0, 0.0, 1.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 1.0, 0.0, 0.0
          ])
        )

      {:ok, program} = MeshShader.load()
      Program.configure_vertex_attribs(program)

      render = fn mvp, normal_matrix, light ->
        GL.bind_framebuffer(:both, fbo)
        GL.viewport(0, 0, size, size)
        clear()

        Program.bind(program)

        Program.set_block(program, :per_frame, %{
          mvp: mvp,
          normal_matrix: normal_matrix,
          light_direction: light,
          base_color: {1.0, 1.0, 1.0, 1.0}
        })

        GL.bind_vertex_array(vao)
        GL.draw_arrays(:triangle_strip, 0, 4)
        GL.assert_no_error!()

        {elem(pixel(size, 4, 8), 0), elem(pixel(size, 12, 8), 0)}
      end

      %{
        render: render,
        identity: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
        # Rotation about Y by -90 degrees, columns not rows: maps +X onto +Z.
        rotate_x_to_z: [0, 0, 1, 0, 1, 0, -1, 0, 0]
      }
    end

    test "mat3 columns are vec4-padded, so the normal rotates onto the light", ctx do
      # Packed as three tight vec3 instead, the shader reads the columns
      # misaligned and the lighting comes out wrong rather than absent.
      assert {left, 0} = ctx.render.(ctx.identity, ctx.rotate_x_to_z, {0.0, 0.0, 1.0})
      assert close?(left, 255)
    end

    test "mat4 is column-major, not transposed", ctx do
      # A translation, not an identity: an identity is symmetric and passes
      # either way, so it cannot detect transposition at all. Column-major puts
      # the offset at elements 12..14; row-major at 3/7/11.
      translate = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1]

      assert {0, right} = ctx.render.(translate, ctx.rotate_x_to_z, {0.0, 0.0, 1.0})
      assert right > 0, "quad did not move - mat4 is likely packed row-major"
    end

    test "intensity tracks the light direction", ctx do
      {towards, _} = ctx.render.(ctx.identity, ctx.rotate_x_to_z, {0.0, 0.0, 1.0})
      {away, _} = ctx.render.(ctx.identity, ctx.rotate_x_to_z, {0.0, 0.0, -1.0})
      {perpendicular, _} = ctx.render.(ctx.identity, ctx.rotate_x_to_z, {0.0, 1.0, 0.0})

      ambient = round(0.15 * 255)

      assert close?(away, ambient), "facing away should sit at the ambient floor"
      assert close?(perpendicular, ambient)
      assert towards > away
    end
  end
end
