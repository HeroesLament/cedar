//! The `:grid` visual — analytic, antialiased gridlines.
//!
//! Gridlines are computed per-fragment from the distance to the nearest cell
//! boundary rather than drawn as geometry. That keeps them exactly one
//! thickness wide at any zoom, antialiases them for free, and avoids either
//! rebuilding a mesh as the viewport changes or watching lines alias into moire
//! when they fall below a pixel.
//!
//! Backs plot gridlines now and the CAD ground plane later.
//!
//! This is the first shader here to use a GPU-only intrinsic: `fwidth`, the
//! rate of change of a value across a pixel, which has no CPU equivalent. The
//! coverage maths still lives in `wx-mvu-shader-core` and takes the derivative
//! as an argument, so everything except the intrinsic itself stays testable on
//! stable Rust.

#![cfg_attr(target_arch = "spirv", no_std)]

use spirv_std::arch::Derivative;
use spirv_std::glam::{vec4, Vec2, Vec4};
use spirv_std::spirv;
use wx_mvu_shader_core::grid_line_alpha;

/// Uniform block. Field order is significant and mirrored in
/// `shaders/shaders.exs` and the `Program` declaration.
///
/// std140: two `vec4` at 0 and 16, `vec2` at 32, `f32` at 40, ending at 44 and
/// rounding to 48.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct Uniforms {
    /// Gridline colour.
    pub line_color: Vec4,
    /// Colour between the lines.
    pub background: Vec4,
    /// Cell size, in the same units as the incoming texture coordinate.
    pub spacing: Vec2,
    /// Line thickness in pixels.
    pub thickness: f32,
}

#[spirv(vertex)]
pub fn main_vs(
    a_position: Vec2,
    a_texcoord: Vec2,
    #[spirv(position)] out_position: &mut Vec4,
    v_texcoord: &mut Vec2,
) {
    *out_position = vec4(a_position.x, a_position.y, 0.0, 1.0);
    *v_texcoord = a_texcoord;
}

#[spirv(fragment)]
pub fn main_fs(
    v_texcoord: Vec2,
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    output: &mut Vec4,
) {
    // Position in grid units: integers are cell boundaries.
    let x = v_texcoord.x / uniforms.spacing.x;
    let y = v_texcoord.y / uniforms.spacing.y;

    // Rate of change across one pixel. Taken per-scalar rather than on the
    // vector so the two axes stay independent, and because fwidth is already
    // an approximation - the coarse/fine variants differ by hardware.
    let dx = x.fwidth();
    let dy = y.fwidth();

    let alpha_x = grid_line_alpha(x, abs(dx), uniforms.thickness);
    let alpha_y = grid_line_alpha(y, abs(dy), uniforms.thickness);

    // A fragment on both a vertical and a horizontal line takes the stronger
    // of the two rather than summing, which would overshoot at intersections.
    let alpha = if alpha_x > alpha_y { alpha_x } else { alpha_y };

    *output = uniforms.background + (uniforms.line_color - uniforms.background) * alpha;
}

#[inline]
fn abs(x: f32) -> f32 {
    if x < 0.0 {
        -x
    } else {
        x
    }
}
