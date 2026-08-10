defmodule WxMVU.GLCanvas.Draw do
  @moduledoc """
  The drawing API available to `WxMVU.GLCanvas` implementations.

  `WxMVU.Renderer.GL` is an internal facade over Erlang's `:gl` and is not part
  of the public surface. This namespace is what canvas authors are meant to
  build against.

  ## Contents

    * `WxMVU.GLCanvas.Draw.Program` - declarative shader programs: uniform
      blocks, sampler units and vertex layout declared once and derived from
      there.
    * `WxMVU.GLCanvas.Draw.Std140` - the std140 layout rules that `Program`
      uses. Usable directly when packing a buffer by hand.

  ## Status

  This namespace is new and currently covers shader programs only. Existing
  canvases still call `WxMVU.Renderer.GL` directly for geometry, textures and
  draw calls; that remains supported but is not the intended long-term shape.

  Two pieces of duplication across the existing canvases are the obvious next
  additions, and are deliberately not built yet:

    * a shared fullscreen-quad VAO/VBO, currently reimplemented identically in
      every canvas that runs a fragment shader over the viewport
    * an R32F data-texture helper wrapping allocate plus `tex_sub_image_2d`

  Neither should be added speculatively - but `Program` is scoped so as not to
  absorb their responsibilities.
  """
end
