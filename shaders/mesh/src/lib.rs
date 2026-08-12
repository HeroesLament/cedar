//! The `:mesh` visual — lit triangle geometry.
//!
//! The workhorse for E-Motion Studio: robot links, imported tessellations,
//! anything with a surface. Blinn-Phong is overkill for a CAD viewport where
//! the job is reading shape rather than simulating materials, so this is
//! Lambert with an ambient floor.
//!
//! Deliberately the largest uniform block in the set, because it is the one
//! that exercises the std140 rules that actually catch people out:
//!
//!   * `mat4` is 64 bytes
//!   * `mat3` is **48**, not 36 — each column is padded out to a `vec4`
//!   * `vec3` occupies 12 bytes but forces the next field to a 16-byte boundary
//!
//! `WxMVU.GLCanvas.Draw.Std140` implements all three, and until this shader
//! existed none of them had been checked against a real driver.

#![cfg_attr(target_arch = "spirv", no_std)]

use spirv_std::glam::{vec3, vec4, Mat3A, Mat4, Vec3, Vec3A, Vec4};
use spirv_std::spirv;
use wx_mvu_shader_core::{lambert_intensity, normalize3};

/// Uniform block. Field order is significant and mirrored in
/// `shaders/shaders.exs` and the `Program` declaration.
///
/// std140: `mvp` at 0 (64), `normal_matrix` at 64 (48), `light_direction` at
/// 112 (12), then `base_color` forced to 128 by vec4 alignment - four bytes of
/// padding at 124 - ending at 144.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct Uniforms {
    /// Combined model-view-projection.
    pub mvp: Mat4,
    /// Inverse transpose of the model matrix, for normals under non-uniform
    /// scale.
    ///
    /// `Mat3A`, not `Mat3`. glam's plain `Mat3` is three tightly packed
    /// `Vec3`, giving columns at 0/12/24 - and std140 requires a 16-byte
    /// column stride. rust-gpu emits glam's CPU layout faithfully, so a `Mat3`
    /// here fails SPIR-V validation with "improperly straddling vector at
    /// offset 76". `Mat3A` is built on `Vec3A` and lays out as 3x16 = 48
    /// bytes, which is exactly what std140 wants.
    pub normal_matrix: Mat3A,
    /// Direction *towards* the light, normalized, in world space.
    pub light_direction: Vec3,
    /// Surface colour.
    pub base_color: Vec4,
}

/// Fraction of full brightness a surface facing away from the light retains.
const AMBIENT: f32 = 0.15;

#[spirv(vertex)]
pub fn main_vs(
    a_position: Vec3,
    a_normal: Vec3,
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    #[spirv(position)] out_position: &mut Vec4,
    v_normal: &mut Vec3,
) {
    *out_position = uniforms.mvp * vec4(a_position.x, a_position.y, a_position.z, 1.0);
    *v_normal = Vec3::from(uniforms.normal_matrix * Vec3A::from(a_normal));
}

#[spirv(fragment)]
pub fn main_fs(
    v_normal: Vec3,
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    output: &mut Vec4,
) {
    // Renormalized because interpolation across a triangle shortens normals,
    // which would otherwise darken face centres.
    //
    // normalize3 rather than glam's normalize_or_zero: the latter guards with
    // is_finite(), which bakes an infinity constant into the SPIR-V, and naga
    // refuses to translate a module containing one.
    let (nx, ny, nz) = normalize3(v_normal.x, v_normal.y, v_normal.z);
    let normal = vec3(nx, ny, nz);
    let intensity = lambert_intensity(normal.dot(uniforms.light_direction), AMBIENT);

    *output = vec4(
        uniforms.base_color.x * intensity,
        uniforms.base_color.y * intensity,
        uniforms.base_color.z * intensity,
        uniforms.base_color.w,
    );
}
