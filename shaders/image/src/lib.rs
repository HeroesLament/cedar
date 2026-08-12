//! The `:image` visual — a data texture sampled through a colormap.
//!
//! Backs `:waterfall`, `:spectrogram`, `:constellation` and any 2D scalar
//! field. See ../../README.md for the GL 4.1 constraints this must respect.
//!
//! Pipeline: rust-gpu -> spirv-unknown-vulkan1.1 -> naga -> GLSL 410.

#![cfg_attr(target_arch = "spirv", no_std)]

use spirv_std::glam::{vec2, vec4, Vec2, Vec4};
use spirv_std::num_traits::Float;
use spirv_std::spirv;
use spirv_std::{Image, Sampler};

/// Sampled 2D float texture. Both the data grid and the colormap LUT use this.
pub type Tex2d = Image!(2D, type=f32, sampled);

/// Uniform block. Field order is significant: it is mirrored on the Elixir
/// side by `WxMVU.GLCanvas.Draw.Program`, and std140 offsets are positional.
///
/// Three consecutive f32 pack to 12 bytes; std140 rounds the block to 16.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct Uniforms {
    /// Normalized scroll position of the ring buffer seam, in [0, 1).
    pub row_offset: f32,
    /// Data value mapped to colormap position 0.0.
    pub domain_min: f32,
    /// Data value mapped to colormap position 1.0.
    pub domain_max: f32,
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
    #[spirv(descriptor_set = 0, binding = 1)] data: &Tex2d,
    #[spirv(descriptor_set = 0, binding = 2)] data_sampler: &Sampler,
    #[spirv(descriptor_set = 0, binding = 3)] colormap: &Tex2d,
    #[spirv(descriptor_set = 0, binding = 4)] colormap_sampler: &Sampler,
    output: &mut Vec4,
) {
    // Ring-buffer scroll. `fract` differs from GLSL `mod(x, 1.0)` on negative
    // inputs; safe here because texcoord.y and row_offset are both in [0, 1].
    let y = (v_texcoord.y + uniforms.row_offset).fract();

    let sample: Vec4 = data.sample(*data_sampler, vec2(v_texcoord.x, y));
    let t = normalize_domain(sample.x, uniforms.domain_min, uniforms.domain_max);

    // Colormap is a 256x1 LUT; sample down the middle of its single row.
    let rgb: Vec4 = colormap.sample(*colormap_sampler, vec2(t, 0.5));

    *output = vec4(rgb.x, rgb.y, rgb.z, 1.0);
}

/// Map a raw value onto [0, 1] given the domain bounds.
///
/// Split out so it compiles for the host too and can be unit tested without a
/// GPU — the payoff for `no_std` rather than a GPU-only crate.
#[inline]
pub fn normalize_domain(value: f32, min: f32, max: f32) -> f32 {
    let span = max - min;
    if span == 0.0 {
        0.0
    } else {
        ((value - min) / span).clamp(0.0, 1.0)
    }
}

#[cfg(all(test, not(target_arch = "spirv")))]
mod tests {
    use super::normalize_domain;

    #[test]
    fn maps_domain_bounds_to_unit_range() {
        assert_eq!(normalize_domain(-100.0, -100.0, 0.0), 0.0);
        assert_eq!(normalize_domain(0.0, -100.0, 0.0), 1.0);
        assert_eq!(normalize_domain(-50.0, -100.0, 0.0), 0.5);
    }

    #[test]
    fn clamps_outside_the_domain() {
        assert_eq!(normalize_domain(-200.0, -100.0, 0.0), 0.0);
        assert_eq!(normalize_domain(50.0, -100.0, 0.0), 1.0);
    }

    #[test]
    fn degenerate_domain_does_not_divide_by_zero() {
        assert_eq!(normalize_domain(5.0, 1.0, 1.0), 0.0);
    }
}
