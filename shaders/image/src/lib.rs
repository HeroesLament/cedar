//! The `:image` visual — a data texture sampled through a colormap.
//!
//! Backs `:waterfall`, `:spectrogram`, `:constellation` and any 2D scalar
//! field. See ../../README.md for the GL 4.1 constraints this must respect.
//!
//! Pipeline: rust-gpu -> spirv-unknown-vulkan1.1 -> naga -> GLSL 410.
//!
//! This crate holds only the entry points and their bindings. The maths lives
//! in `cedar-shader-core`, which has no `spirv-std` dependency and therefore
//! tests on stable Rust.

#![cfg_attr(target_arch = "spirv", no_std)]

use spirv_std::glam::{vec2, vec4, Vec2, Vec4};
use spirv_std::spirv;
use spirv_std::{Image, Sampler};
use cedar_shader_core::{normalize_domain, wrap_unit};

/// Sampled 2D float texture. Both the data grid and the colormap LUT use this.
pub type Tex2d = Image!(2D, type=f32, sampled);

/// Uniform block. Field order is significant: it is mirrored on the Elixir
/// side by `Cedar.GLCanvas.Draw.Program` and in `shaders/shaders.exs`, and
/// std140 offsets are positional.
///
/// Three consecutive f32 pack to 12 bytes; std140 rounds the block to 16.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct Uniforms {
    /// Normalized scroll position of the ring buffer seam.
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
    // wrap_unit rather than .fract(): Rust's fract truncates and stays negative
    // for negative input, so scrolling backwards through history would sample
    // outside the texture. See cedar_shader_core::wrap_unit.
    let y = wrap_unit(v_texcoord.y + uniforms.row_offset);

    let sample: Vec4 = data.sample(*data_sampler, vec2(v_texcoord.x, y));
    let t = normalize_domain(sample.x, uniforms.domain_min, uniforms.domain_max);

    // Colormap is a 256x1 LUT; sample down the middle of its single row.
    let rgb: Vec4 = colormap.sample(*colormap_sampler, vec2(t, 0.5));

    *output = vec4(rgb.x, rgb.y, rgb.z, 1.0);
}
