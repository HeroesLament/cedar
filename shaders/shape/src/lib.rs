//! The `:shape` visual — analytic 2D primitives from signed distance fields.
//!
//! Covers rectangles, rounded rectangles, circles, ellipses, pie sectors and
//! arcs, filled and stroked, with solid or gradient paint. One program, one
//! draw call per shape, no tessellation anywhere.
//!
//! ## Why this is a formula and not a mesh
//!
//! The obvious way to draw a rounded rectangle is to tessellate it: flatten
//! each corner arc into segments, fan the interior into triangles, rebuild the
//! buffer whenever the radius or the size changes, and pick a segment count
//! that is smooth enough when zoomed in without being wasteful when zoomed out.
//! Stroking then needs a second, different mesh - the offset outline - with its
//! own joins and caps.
//!
//! Evaluating a distance function per fragment avoids all of it. The shape is
//! exact at every size, the antialiasing falls out of the distance, and the
//! stroke is the same formula with one subtraction. Nothing is rebuilt when a
//! corner radius animates; a uniform changes.
//!
//! ## Why there is no circle branch
//!
//! A square whose corner radius is half its side *is* a circle - exactly, not
//! approximately. So `:circle` is the rounded-box path with a radius the host
//! fills in, and the fragment shader has one fewer branch for it.
//!
//! ## Pixels all the way down
//!
//! Vertices arrive in pixels with the origin at the top left, like `:text`,
//! because that is the coordinate system a UI layout produces. The distance
//! functions therefore return pixels too, which is what lets coverage be a
//! plain subtraction rather than a `fwidth`. See `shape_coverage` in
//! `cedar-shader-core` for why that matters.
//!
//! ## No trigonometry
//!
//! Sectors and arcs need angles, and this shader contains none. The host turns
//! every angle into a sine and a cosine once per draw call, so the fragment
//! shader does a rotation and two dot products - and never depends on `atan2`,
//! whose branch cut and precision vary across drivers.
//!
//! Pipeline: rust-gpu -> spirv-unknown-vulkan1.1 -> naga -> GLSL 410.

#![cfg_attr(target_arch = "spirv", no_std)]

use spirv_std::glam::{vec2, vec4, Vec2, Vec4};
use spirv_std::spirv;

use cedar_shader_core::{
    arc_distance, ellipse_distance, linear_gradient_t, pie_distance, quadrant_radius,
    radial_gradient_t, rotate2, rounded_box_distance, shape_coverage, stroke_distance,
};

/// Uniform block. Field order is significant and mirrored in
/// `shaders/shaders.exs` and the `Program` declaration.
///
/// std140: seven `vec4` at 0..112, two `vec2` at 112 and 120, five `f32` at
/// 128..148, block rounded to 160.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct Uniforms {
    /// Fill colour, or the start colour when a gradient is active.
    pub fill_color: Vec4,
    /// Gradient end colour. Ignored when `gradient_kind` is zero.
    pub fill_color1: Vec4,
    /// Stroke colour. Its alpha multiplies the stroke coverage.
    pub stroke_color: Vec4,
    /// Corner radii, clockwise from the top left: tl, tr, br, bl.
    pub radii: Vec4,
    /// The shape's box in pixels: x, y, width, height.
    pub rect: Vec4,
    /// Gradient geometry. Linear uses all four as two endpoints; radial uses
    /// centre in xy and radius in z.
    pub gradient: Vec4,
    /// Wedge orientation for sectors and arcs: cos and sin of the rotation
    /// that brings the wedge upright, then sin and cos of half its aperture.
    pub wedge: Vec4,
    /// Framebuffer size in pixels.
    pub viewport: Vec2,
    /// Arc band: centreline radius, half thickness.
    pub arc: Vec2,
    /// Stroke width in pixels. Zero draws no stroke.
    pub stroke_width: f32,
    /// 0 rounded box, 1 ellipse, 2 sector, 3 arc.
    pub shape: f32,
    /// 0 solid, 1 linear, 2 radial.
    pub gradient_kind: f32,
    /// Distance added to the fill, in logical pixels. Negative insets it.
    pub inset: f32,
    /// Physical pixels per logical pixel.
    ///
    /// Everything else here is in logical units, because that is what a layout
    /// produces and what `:text` already uses. Antialiasing is not a logical
    /// quantity though - the ramp has to span one *physical* pixel or the edge
    /// is twice as soft as it should be on a Retina display. Multiplying the
    /// distance by this before taking coverage is the whole correction, and
    /// it is the same mistake `:text` guards against with `px_range`.
    pub pixel_scale: f32,
}

/// Expands a unit quad to cover the shape's box plus a margin.
///
/// The margin matters. Antialiasing needs half a pixel outside the outline and
/// a stroke needs half its width, so a quad drawn tight to the rectangle would
/// clip its own soft edge and leave the shape looking bitten off along its
/// bounds.
#[spirv(vertex)]
pub fn main_vs(
    a_corner: Vec2,
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    #[spirv(position)] out_position: &mut Vec4,
    v_local: &mut Vec2,
) {
    let margin = uniforms.stroke_width * 0.5 + 2.0;

    let width = uniforms.rect.z + margin * 2.0;
    let height = uniforms.rect.w + margin * 2.0;

    let x = uniforms.rect.x - margin + a_corner.x * width;
    let y = uniforms.rect.y - margin + a_corner.y * height;

    // Local space: pixels, origin at the shape's centre, Y down. Every
    // distance function below is written for a shape centred on the origin,
    // so the centring happens once here rather than in each of them.
    let cx = uniforms.rect.x + uniforms.rect.z * 0.5;
    let cy = uniforms.rect.y + uniforms.rect.w * 0.5;
    *v_local = vec2(x - cx, y - cy);

    // Pixels, top-left origin, to clip space. Y flips because the layout
    // above advances downwards, as every UI coordinate system does.
    let ndc_x = x / uniforms.viewport.x * 2.0 - 1.0;
    let ndc_y = 1.0 - y / uniforms.viewport.y * 2.0;

    *out_position = vec4(ndc_x, ndc_y, 0.0, 1.0);
}

#[spirv(fragment)]
pub fn main_fs(
    v_local: Vec2,
    #[spirv(uniform, descriptor_set = 0, binding = 0)] uniforms: &Uniforms,
    output: &mut Vec4,
) {
    let half_w = uniforms.rect.z * 0.5;
    let half_h = uniforms.rect.w * 0.5;

    // The branch is on a uniform, so every fragment in the draw takes the same
    // path and there is no divergence to pay for.
    let distance = if uniforms.shape < 0.5 {
        let radius = quadrant_radius(
            v_local.x,
            v_local.y,
            uniforms.radii.x,
            uniforms.radii.y,
            uniforms.radii.z,
            uniforms.radii.w,
        );

        rounded_box_distance(v_local.x, v_local.y, half_w, half_h, radius)
    } else if uniforms.shape < 1.5 {
        ellipse_distance(v_local.x, v_local.y, half_w, half_h)
    } else {
        // Sectors and arcs are defined opening along +Y and rotated into
        // place, so there is one wedge implementation rather than one per
        // orientation.
        let (rx, ry) = rotate2(v_local.x, v_local.y, uniforms.wedge.x, uniforms.wedge.y);

        if uniforms.shape < 2.5 {
            let radius = if half_w < half_h { half_w } else { half_h };
            pie_distance(rx, ry, uniforms.wedge.z, uniforms.wedge.w, radius)
        } else {
            arc_distance(
                rx,
                ry,
                uniforms.wedge.z,
                uniforms.wedge.w,
                uniforms.arc.x,
                uniforms.arc.y,
            )
        }
    };

    let distance = distance + uniforms.inset;

    // Paint. Gradient position is measured in the same local pixel space as
    // the shape, so a gradient declared across a shape's own box does not have
    // to be respecified when the shape moves.
    let t = if uniforms.gradient_kind < 0.5 {
        0.0
    } else if uniforms.gradient_kind < 1.5 {
        linear_gradient_t(
            v_local.x,
            v_local.y,
            uniforms.gradient.x,
            uniforms.gradient.y,
            uniforms.gradient.z,
            uniforms.gradient.w,
        )
    } else {
        radial_gradient_t(
            v_local.x,
            v_local.y,
            uniforms.gradient.x,
            uniforms.gradient.y,
            uniforms.gradient.z,
        )
    };

    let fill = uniforms.fill_color + (uniforms.fill_color1 - uniforms.fill_color) * t;

    // Into physical pixels for the coverage step only - see `pixel_scale`.
    let scale = uniforms.pixel_scale;

    let fill_alpha = shape_coverage(distance * scale) * fill.w;

    let stroke_alpha = if uniforms.stroke_width > 0.0 {
        shape_coverage(stroke_distance(distance, uniforms.stroke_width * 0.5) * scale)
            * uniforms.stroke_color.w
    } else {
        0.0
    };

    // Stroke over fill, straight alpha. Straight rather than premultiplied so
    // the colour uniforms mean the same thing regardless of coverage - the
    // same choice `:text` makes, and for the same reason.
    let alpha = stroke_alpha + fill_alpha * (1.0 - stroke_alpha);

    if alpha <= 0.0 {
        *output = vec4(0.0, 0.0, 0.0, 0.0);
    } else {
        let weight = fill_alpha * (1.0 - stroke_alpha);

        let r = (uniforms.stroke_color.x * stroke_alpha + fill.x * weight) / alpha;
        let g = (uniforms.stroke_color.y * stroke_alpha + fill.y * weight) / alpha;
        let b = (uniforms.stroke_color.z * stroke_alpha + fill.z * weight) / alpha;

        *output = vec4(r, g, b, alpha);
    }
}
