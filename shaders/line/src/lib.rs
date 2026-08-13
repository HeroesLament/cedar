//! The `:line` visual — a polyline drawn as expanded quads.
//!
//! `glLineWidth` above 1.0 is unreliable to unsupported in an OpenGL 4.1 core
//! profile, so any line thicker than a hairline has to be geometry. Each
//! segment arrives as vertices carrying the point, its neighbour along the
//! segment, and which side of the line to offset towards; the vertex shader
//! does the expansion in screen space so the width stays constant in pixels
//! regardless of zoom.
//!
//! Backs `:line`, `:scope`, `:spectrum_trace`, axis rules and grid lines.
//!
//! Deliberately unlike `:image` in shape, as a second case for the pipeline:
//! a uniform block with mixed alignments rather than three floats, no samplers
//! at all, three vertex attributes rather than two, and a block referenced from
//! both stages rather than the fragment alone.

#![cfg_attr(target_arch = "spirv", no_std)]

use spirv_std::glam::{vec2, vec4, Vec2, Vec4};
use spirv_std::spirv;
use cedar_shader_core::perpendicular2;

/// Uniform block. Field order is significant and mirrored in
/// `shaders/shaders.exs` and the `Program` declaration.
///
/// std140 puts `color` at 0 (16 bytes), `viewport` at 16 — a `vec2` aligns to
/// 8 — and `line_width` at 24, ending at 28. The block then rounds up to 32.
/// Four of those bytes are pure padding, which is exactly the sort of thing
/// nobody gets right by hand.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct Uniforms {
    /// Line colour, straight through to the fragment output.
    pub color: Vec4,
    /// Framebuffer size in pixels, for converting a pixel width into NDC.
    pub viewport: Vec2,
    /// Line width in pixels.
    pub line_width: f32,
}

#[spirv(vertex)]
pub fn main_vs(
    a_position: Vec2,
    a_neighbor: Vec2,
    a_side: f32,
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    #[spirv(position)] out_position: &mut Vec4,
) {
    // Expansion happens in NDC, corrected for aspect so the width is uniform
    // in pixels rather than stretched along whichever axis is longer.
    let direction = a_neighbor - a_position;
    let (px, py) = perpendicular2(direction.x * uniforms.viewport.x, direction.y * uniforms.viewport.y);

    // Half-width, converted from pixels back into NDC per axis.
    let half = uniforms.line_width * 0.5;
    let offset = vec2(
        px * half * 2.0 / uniforms.viewport.x,
        py * half * 2.0 / uniforms.viewport.y,
    );

    let expanded = a_position + offset * a_side;

    *out_position = vec4(expanded.x, expanded.y, 0.0, 1.0);
}

#[spirv(fragment)]
pub fn main_fs(
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    output: &mut Vec4,
) {
    *output = uniforms.color;
}
