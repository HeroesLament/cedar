//! The `:text` visual — glyphs from a signed distance field atlas.
//!
//! Text is the one visual whose *source data* is not a shader problem. Getting
//! a glyph's outline into a texture needs a font rasterizer, which is why the
//! atlas is baked ahead of time by `tools/atlas` and committed alongside the
//! generated GLSL. This shader only has to reconstruct a crisp edge from the
//! field.
//!
//! ## Why SDF rather than a glyph bitmap
//!
//! A bitmap atlas is sharp at exactly one size. Everything else is either a
//! blur or a staircase, and a viewport with a zoom control visits every size
//! there is. A distance field stores how far each texel is from the glyph
//! outline, so the edge can be reconstructed at any scale from a single
//! texture — one 512x512 atlas covers 8pt labels and a 200pt title equally
//! well.
//!
//! ## Why the smoothing width is a uniform and not `fwidth`
//!
//! The usual formulation derives the screen-space width of one distance unit
//! from fragment derivatives. That works, but it makes the antialiasing depend
//! on a per-fragment quantity for information the host already knows exactly:
//! the ratio between the font size being drawn and the size the atlas was
//! baked at is a constant for the whole draw call. Passing it as `px_range`
//! keeps the fragment shader free of derivative instructions — which are the
//! part of the SPIR-V-to-GLSL translation most likely to differ across naga
//! versions — and makes the coverage exactly reproducible in a host-side test.
//!
//! Pipeline: rust-gpu -> spirv-unknown-vulkan1.1 -> naga -> GLSL 410.

#![cfg_attr(target_arch = "spirv", no_std)]

use spirv_std::glam::{vec4, Vec2, Vec4};
use spirv_std::spirv;
use spirv_std::{Image, Sampler};
use wx_mvu_shader_core::sdf_coverage;

/// The distance field atlas: single-channel, sampled as f32.
pub type Tex2d = Image!(2D, type=f32, sampled);

/// Uniform block. Field order is significant and mirrored in
/// `shaders/shaders.exs` and the `Program` declaration.
///
/// std140: `color` at 0 (16), `viewport` at 16 (8), `px_range` at 24 (4),
/// block rounded to 32.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct Uniforms {
    /// Text colour. Its alpha multiplies the glyph coverage, so fading a label
    /// out is a uniform write rather than a re-layout.
    pub color: Vec4,
    /// Framebuffer size in pixels. Vertices arrive in pixels with the origin
    /// at the top left, because that is the coordinate system text layout
    /// naturally produces, and this converts them to clip space.
    pub viewport: Vec2,
    /// Screen pixels spanned by the atlas's full distance range.
    ///
    /// The host knows this exactly: it is the baked range in atlas pixels
    /// times the ratio of the drawn size to the baked size. Small values are
    /// what make small text soft rather than jagged; large values sharpen it.
    pub px_range: f32,
}

#[spirv(vertex)]
pub fn main_vs(
    a_position: Vec2,
    a_texcoord: Vec2,
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    #[spirv(position)] out_position: &mut Vec4,
    v_texcoord: &mut Vec2,
) {
    // Pixels, top-left origin, to clip space. Y is flipped rather than the
    // layout being written upside down: a baseline that advances downwards is
    // what every font metric in existence assumes.
    let x = a_position.x / uniforms.viewport.x * 2.0 - 1.0;
    let y = 1.0 - a_position.y / uniforms.viewport.y * 2.0;

    *out_position = vec4(x, y, 0.0, 1.0);
    *v_texcoord = a_texcoord;
}

#[spirv(fragment)]
pub fn main_fs(
    v_texcoord: Vec2,
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    #[spirv(descriptor_set = 0, binding = 1)] atlas: &Tex2d,
    #[spirv(descriptor_set = 0, binding = 2)] atlas_sampler: &Sampler,
    output: &mut Vec4,
) {
    let sample: Vec4 = atlas.sample(*atlas_sampler, v_texcoord);
    let coverage = sdf_coverage(sample.x, uniforms.px_range);

    // Straight alpha. The visual enables blending; premultiplying here would
    // make the colour uniform mean something different depending on coverage.
    *output = vec4(
        uniforms.color.x,
        uniforms.color.y,
        uniforms.color.z,
        uniforms.color.w * coverage,
    );
}
