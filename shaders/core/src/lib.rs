//! Shader math shared across cedar's shaders.
//!
//! This crate deliberately has **no dependency on `spirv-std`**, and must not
//! acquire one. That is what lets it build and test on stable Rust: `spirv-std`
//! uses unstable features (`cfg_select!`), so anything depending on it — even a
//! host build — requires the pinned nightly.
//!
//! Shader entry points live in the per-shader crates and need the nightly.
//! Everything they can express as a pure function belongs here instead, where
//! it is testable on the CPU with no GPU, no graphics context, and no
//! toolchain ceremony. That split is the practical argument for writing
//! shaders in Rust rather than GLSL, so it is worth keeping clean.
//!
//! `mix cedar.shaders.test` runs this crate on stable specifically to catch a
//! `spirv-std` dependency creeping in.

#![cfg_attr(not(test), no_std)]

/// Maps a raw value onto `[0, 1]` given inclusive domain bounds, clamping
/// outside them.
///
/// This is the scale step of every data visual: dB into a colormap position
/// for a waterfall, density for a constellation, magnitude for a heatmap.
///
/// A zero-width domain yields `0.0` rather than a division by zero. That case
/// is reachable from the UI — a user dragging both ends of a range control
/// together — so it must not produce `NaN` and paint the viewport black.
#[inline]
pub fn normalize_domain(value: f32, min: f32, max: f32) -> f32 {
    let span = max - min;

    if span == 0.0 {
        0.0
    } else {
        clamp_unit((value - min) / span)
    }
}

/// Clamps to `[0, 1]`.
///
/// Written as comparisons rather than `f32::clamp` because that is what the
/// GPU path lowers to anyway, and because it keeps the function free of
/// anything that behaves differently under `no_std`.
#[inline]
pub fn clamp_unit(t: f32) -> f32 {
    if t < 0.0 {
        0.0
    } else if t > 1.0 {
        1.0
    } else {
        t
    }
}

/// Wraps to `[0, 1)`, matching GLSL's `fract` rather than Rust's.
///
/// Rust's `f32::fract` truncates, so it returns a negative value for negative
/// input; GLSL's `fract` is `x - floor(x)` and never does. The generated GLSL
/// for a Rust `.fract()` comes out as `x - trunc(x)`, which is only equivalent
/// for non-negative input.
///
/// Ring-buffer scrolling can legitimately go negative — scrolling backwards
/// through history — so use this rather than `.fract()` anywhere the input is
/// not provably non-negative.
#[inline]
pub fn wrap_unit(x: f32) -> f32 {
    let wrapped = x - floor_f32(x);

    // Guards the edge case where x is a very small negative number: the
    // subtraction can round to exactly 1.0, which is outside [0, 1).
    if wrapped >= 1.0 {
        0.0
    } else {
        wrapped
    }
}

/// `floor` without `std`, and without `libm` as a dependency.
#[inline]
fn floor_f32(x: f32) -> f32 {
    let truncated = x as i32 as f32;

    if x < 0.0 && truncated != x {
        truncated - 1.0
    } else {
        truncated
    }
}

/// Normalizes a 2D vector, returning `(0.0, 0.0)` for a zero-length input.
///
/// Scalar in and out rather than `glam::Vec2` so this crate stays
/// dependency-free — see the module docs. The shader crates reassemble vectors
/// on the other side.
///
/// Degenerate input is reachable: a polyline with a repeated point produces a
/// zero-length segment, and normalizing it would otherwise yield `NaN` and
/// smear the whole primitive across the viewport.
#[inline]
pub fn normalize2(x: f32, y: f32) -> (f32, f32) {
    // Scaled before squaring, for the same overflow reason as `normalize3`.
    let scale = if abs_f32(x) > abs_f32(y) {
        abs_f32(x)
    } else {
        abs_f32(y)
    };

    if scale <= 0.0 {
        return (0.0, 0.0);
    }

    let (x, y) = (x / scale, y / scale);
    let inverse = 1.0 / sqrt_f32(x * x + y * y);

    (x * inverse, y * inverse)
}

/// Normalizes a 3D vector, returning `(0.0, 0.0, 0.0)` for a zero-length input.
///
/// Deliberately not `glam::Vec3::normalize_or_zero`. That guards itself with
/// `is_finite()`, which compiles to a comparison against an infinity constant -
/// and naga rejects the resulting SPIR-V outright with "Float literal is
/// infinite", so the shader never reaches GLSL. Comparing the squared length
/// against zero achieves the same guard without ever materialising an infinity.
///
/// Degenerate normals are reachable from real data: a mesh with a zero-area
/// triangle, or a normal attribute left at zero by an exporter.
#[inline]
pub fn normalize3(x: f32, y: f32, z: f32) -> (f32, f32, f32) {
    // Scale by the largest component before squaring. Squaring directly
    // overflows f32 for inputs above ~1.8e19 - a coordinate of 1e30 gives a
    // length_squared of infinity, and Newton-Raphson on infinity yields NaN,
    // which then propagates into the normal and blackens the surface.
    //
    // Scaling first keeps every squared term within [0, 1] regardless of the
    // input's magnitude, so no intermediate can overflow, and it does so
    // without an `is_finite` check - which would compile to a comparison
    // against an infinity constant and be rejected by naga.
    let scale = max3(abs_f32(x), abs_f32(y), abs_f32(z));

    if scale <= 0.0 {
        return (0.0, 0.0, 0.0);
    }

    let (x, y, z) = (x / scale, y / scale, z / scale);
    let inverse = 1.0 / sqrt_f32(x * x + y * y + z * z);

    (x * inverse, y * inverse, z * inverse)
}

/// Largest of three values.
#[inline]
fn max3(a: f32, b: f32, c: f32) -> f32 {
    let ab = if a > b { a } else { b };

    if ab > c {
        ab
    } else {
        c
    }
}

/// The left-hand perpendicular of a 2D direction, normalized.
///
/// This is the line-expansion primitive: a polyline is drawn as quads offset
/// along the perpendicular of each segment, because `glLineWidth` above 1.0 is
/// unreliable to unsupported in an OpenGL 4.1 core profile.
#[inline]
pub fn perpendicular2(x: f32, y: f32) -> (f32, f32) {
    let (nx, ny) = normalize2(x, y);
    (-ny, nx)
}

/// `sqrt` without `std`.
///
/// Newton-Raphson from a scaled initial guess. On the GPU this lowers to the
/// hardware instruction; this path only runs in host tests.
#[inline]
fn sqrt_f32(x: f32) -> f32 {
    if x <= 0.0 {
        return 0.0;
    }

    let mut guess = x;
    let mut i = 0;

    while i < 20 {
        let next = 0.5 * (guess + x / guess);

        if next == guess {
            break;
        }

        guess = next;
        i += 1;
    }

    guess
}

/// Coverage of a gridline at `coord`, as an alpha in `[0, 1]`.
///
/// `coord` is a position in grid units, so gridlines sit at every integer.
/// `derivative` is how much `coord` changes across one pixel — on the GPU that
/// comes from `fwidth`, which has no CPU equivalent, which is why this function
/// takes it as an argument rather than computing it. That keeps the interesting
/// part testable here and leaves only the intrinsic in the shader.
///
/// Analytic rather than geometric: gridlines are computed per-fragment from the
/// distance to the nearest integer, so they stay one thickness wide at any zoom
/// and antialias for free. Drawing them as geometry means either a mesh that
/// changes with the viewport, or moire at low zoom.
#[inline]
pub fn grid_line_alpha(coord: f32, derivative: f32, thickness: f32) -> f32 {
    // A zero derivative means the coordinate is constant across the pixel,
    // which happens on degenerate geometry. Dividing by it would give inf.
    if derivative <= 0.0 || thickness <= 0.0 {
        return 0.0;
    }

    // Distance to the nearest integer, in grid units, in [0, 0.5].
    let distance = abs_f32(wrap_unit(coord - 0.5) - 0.5);

    // Converted to pixels from the centre of the line.
    let pixels = distance / derivative;

    // Box-filter coverage: how much of this pixel the band actually covers,
    // treating the pixel as a unit-wide box centred on its sample point.
    //
    // The obvious formula - a linear ramp from 1 at the centre to 0 at
    // `thickness / 2` - is wrong at hairline widths. Gridlines land on integer
    // coordinates, which typically fall on pixel *boundaries*, putting every
    // sample point half a pixel away. A 1px line then evaluates to exactly 0 on
    // both neighbours and disappears completely. The `+ 0.5` is what gives each
    // neighbour half coverage instead, so a 1px line renders as 1px of ink.
    clamp_unit(thickness * 0.5 - pixels + 0.5)
}

/// `abs` without `std`.
#[inline]
fn abs_f32(x: f32) -> f32 {
    if x < 0.0 {
        -x
    } else {
        x
    }
}

/// Lambertian diffuse intensity with an ambient floor.
///
/// `n_dot_l` is the dot product of the surface normal and the direction to the
/// light, both normalized. `ambient` is the fraction of full brightness a
/// surface facing directly away still receives.
///
/// The ambient floor is not cosmetic. With pure Lambert, geometry facing away
/// from the light renders pure black and its silhouette disappears against the
/// background - which in a CAD viewport means a robot arm that vanishes when it
/// rotates. Every real viewport has some floor.
#[inline]
pub fn lambert_intensity(n_dot_l: f32, ambient: f32) -> f32 {
    let ambient = clamp_unit(ambient);
    let diffuse = clamp_unit(n_dot_l);

    ambient + (1.0 - ambient) * diffuse
}

/// Antialiased coverage for a signed distance field sample.
///
/// `distance` is the sampled field value, where `0.5` is exactly on the glyph
/// outline, above is inside, below is outside. `px_range` is how many *screen*
/// pixels the field's full `0.0..1.0` range spans at the size being drawn.
///
/// The result is a box-filter coverage estimate: the fraction of a one-pixel
/// square the glyph covers, assuming the edge is locally straight. That is the
/// same model `grid_line_alpha` uses, and for the same reason - a linear ramp
/// across the pixel makes hairlines and small text vanish rather than merely
/// soften, because the ramp never reaches full coverage on a feature narrower
/// than one pixel.
///
/// A `px_range` of zero - which a caller reaches by drawing text at size zero -
/// yields a hard threshold rather than a division by zero.
#[inline]
pub fn sdf_coverage(distance: f32, px_range: f32) -> f32 {
    clamp_unit((distance - 0.5) * px_range + 0.5)
}

// ==========================================================================
// Analytic 2D shapes
// ==========================================================================
//
// Every shape below is a signed distance function: negative inside, positive
// outside, zero on the outline, and measured in the same units as the point
// passed in. The `:shape` visual works in pixels, so one unit of distance is
// one pixel, which is what makes `shape_coverage` a plain subtraction with no
// derivative anywhere.
//
// That is the whole reason to draw UI this way. A rounded rectangle is not
// tessellated into a fan of triangles that has to be rebuilt whenever a corner
// radius changes; it is a formula evaluated per fragment, exact at any size,
// antialiased for free, and stroked by evaluating the same formula twice.

/// Coverage of a shape whose signed distance is expressed in **pixels**.
///
/// Box-filter estimate: the fraction of a one-pixel square the shape covers,
/// assuming the edge is locally straight. Identical in spirit to
/// `grid_line_alpha` and `sdf_coverage`, and identical in motivation - a linear
/// ramp across the pixel makes hairline strokes vanish rather than merely
/// soften.
///
/// Takes no derivative, unlike the usual `fwidth`-based formulation. It does
/// not need one: the distance is already in pixels, so the rate of change
/// across a pixel is one by construction. That keeps the fragment shader free
/// of derivative instructions - which are the part of the SPIR-V-to-GLSL
/// translation most likely to shift between naga versions - and makes coverage
/// exactly reproducible in a host-side test.
#[inline]
pub fn shape_coverage(distance: f32) -> f32 {
    clamp_unit(0.5 - distance)
}

/// Turns a fill distance into a stroke distance.
///
/// The outline of a shape is the set of points within `half_width` of its
/// zero contour, which is exactly `abs(d) - half_width`. So a stroke costs one
/// subtraction on top of a fill, and stroke and fill can never disagree about
/// where the edge is - they are the same number.
#[inline]
pub fn stroke_distance(distance: f32, half_width: f32) -> f32 {
    abs_f32(distance) - half_width
}

/// Signed distance to an axis-aligned rounded box centred on the origin.
///
/// `radius` is the corner radius for the quadrant `(px, py)` falls in - see
/// `quadrant_radius` - and is clamped to half the shorter side, so an absurd
/// radius degrades to a stadium rather than turning inside out.
///
/// Covers more primitives than its name suggests. A zero radius is a
/// rectangle. A square with radius equal to half its side is an exact circle,
/// not an approximation of one, which is why the `:shape` visual has no
/// separate circle path.
#[inline]
pub fn rounded_box_distance(px: f32, py: f32, half_w: f32, half_h: f32, radius: f32) -> f32 {
    let limit = if half_w < half_h { half_w } else { half_h };
    let r = if radius > limit { limit } else { radius };
    let r = if r < 0.0 { 0.0 } else { r };

    let qx = abs_f32(px) - half_w + r;
    let qy = abs_f32(py) - half_h + r;

    let ax = if qx > 0.0 { qx } else { 0.0 };
    let ay = if qy > 0.0 { qy } else { 0.0 };

    let outside = sqrt_f32(ax * ax + ay * ay);
    let inside = {
        let m = if qx > qy { qx } else { qy };
        if m < 0.0 {
            m
        } else {
            0.0
        }
    };

    outside + inside - r
}

/// Picks the corner radius for the quadrant a point falls in.
///
/// Corners are named clockwise from the top left, matching CSS and the screen's
/// Y-down convention: a positive `py` is below the centre.
#[inline]
pub fn quadrant_radius(
    px: f32,
    py: f32,
    top_left: f32,
    top_right: f32,
    bottom_right: f32,
    bottom_left: f32,
) -> f32 {
    if py < 0.0 {
        if px < 0.0 {
            top_left
        } else {
            top_right
        }
    } else if px < 0.0 {
        bottom_left
    } else {
        bottom_right
    }
}

/// Signed distance to an axis-aligned ellipse centred on the origin.
///
/// An approximation, deliberately. The exact signed distance to an ellipse has
/// no closed form - it needs a root of a quartic, solved iteratively - and a
/// loop in a fragment shader costs far more than the error is worth at UI
/// sizes. This is the standard gradient-scaled form, which is exact on the
/// axes and errs by well under a pixel elsewhere for the aspect ratios a UI
/// produces.
///
/// Degenerate radii return the distance to the centre rather than dividing by
/// zero: an ellipse can reach zero width through a layout animation, and it
/// must fade out rather than fill the viewport with `NaN`.
#[inline]
pub fn ellipse_distance(px: f32, py: f32, rx: f32, ry: f32) -> f32 {
    if rx <= 0.0 || ry <= 0.0 {
        return sqrt_f32(px * px + py * py);
    }

    let ux = px / rx;
    let uy = py / ry;
    let k1 = sqrt_f32(ux * ux + uy * uy);

    let vx = px / (rx * rx);
    let vy = py / (ry * ry);
    let k2 = sqrt_f32(vx * vx + vy * vy);

    if k2 <= 0.0 {
        // Dead centre. The nearest point on the outline is the shorter radius
        // away, and the point is inside, so the distance is negative.
        return if rx < ry { -rx } else { -ry };
    }

    k1 * (k1 - 1.0) / k2
}

/// Signed distance to a pie slice centred on the origin, opening along +Y.
///
/// `sin_half` and `cos_half` are the sine and cosine of *half* the slice's
/// aperture, computed by the host. The point is expected to have been rotated
/// into the slice's frame by `rotate2` first.
///
/// No trigonometry appears here or in the shader. Every angle a caller cares
/// about is turned into a sine and a cosine once, on the CPU, per draw call -
/// rather than per fragment, and rather than relying on `atan2`, whose
/// precision and branch-cut handling vary across drivers.
#[inline]
pub fn pie_distance(px: f32, py: f32, sin_half: f32, cos_half: f32, radius: f32) -> f32 {
    // Mirrored about X so only half the wedge has to be considered.
    let px = abs_f32(px);

    // Distance to the bounding disc.
    let disc = sqrt_f32(px * px + py * py) - radius;

    // Distance to the straight edge, as a segment from the origin outwards.
    let dot = px * sin_half + py * cos_half;
    let t = if dot < 0.0 {
        0.0
    } else if dot > radius {
        radius
    } else {
        dot
    };

    let ex = px - sin_half * t;
    let ey = py - cos_half * t;
    let edge = sqrt_f32(ex * ex + ey * ey);

    // Sign of the edge term: positive outside the wedge, negative inside.
    let side = cos_half * px - sin_half * py;
    let edge = if side > 0.0 { edge } else { -edge };

    if disc > edge {
        disc
    } else {
        edge
    }
}

/// Signed distance to an arc - a band of a ring - centred on the origin and
/// opening along +Y.
///
/// `mid_radius` is the centreline of the band and `half_thickness` its half
/// width, so an arc is stroked by construction rather than by outlining a fill.
/// As with `pie_distance`, the point arrives already rotated and the aperture
/// arrives as a sine and cosine.
#[inline]
pub fn arc_distance(
    px: f32,
    py: f32,
    sin_half: f32,
    cos_half: f32,
    mid_radius: f32,
    half_thickness: f32,
) -> f32 {
    let px = abs_f32(px);

    let within_wedge = cos_half * px <= sin_half * py;

    let d = if within_wedge {
        // Inside the angular span: distance to the centreline circle.
        abs_f32(sqrt_f32(px * px + py * py) - mid_radius)
    } else {
        // Past the end: distance to the cap centre, which rounds the ends.
        let cx = sin_half * mid_radius;
        let cy = cos_half * mid_radius;
        let ex = px - cx;
        let ey = py - cy;
        sqrt_f32(ex * ex + ey * ey)
    };

    d - half_thickness
}

/// Rotates a point by a precomputed cosine and sine.
///
/// Separate from the shape functions because the shapes are all defined in a
/// canonical orientation and rotated into place, rather than each carrying its
/// own angle handling.
#[inline]
pub fn rotate2(px: f32, py: f32, cos_t: f32, sin_t: f32) -> (f32, f32) {
    (px * cos_t - py * sin_t, px * sin_t + py * cos_t)
}

/// Position along a linear gradient, in `[0, 1]`.
///
/// The projection of the point onto the axis from `(x0, y0)` to `(x1, y1)`,
/// clamped. A zero-length axis yields `0.0` rather than `NaN` - reachable by
/// animating a gradient's endpoints together.
#[inline]
pub fn linear_gradient_t(px: f32, py: f32, x0: f32, y0: f32, x1: f32, y1: f32) -> f32 {
    let ax = x1 - x0;
    let ay = y1 - y0;
    let len_sq = ax * ax + ay * ay;

    if len_sq <= 0.0 {
        return 0.0;
    }

    clamp_unit(((px - x0) * ax + (py - y0) * ay) / len_sq)
}

/// Position along a radial gradient, in `[0, 1]`.
///
/// Distance from the centre over the radius, clamped. A zero radius yields
/// `1.0`, so a collapsed radial gradient reads as its outer colour rather than
/// flickering between the two.
#[inline]
pub fn radial_gradient_t(px: f32, py: f32, cx: f32, cy: f32, radius: f32) -> f32 {
    if radius <= 0.0 {
        return 1.0;
    }

    let dx = px - cx;
    let dy = py - cy;

    clamp_unit(sqrt_f32(dx * dx + dy * dy) / radius)
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert!(normalize_domain(5.0, 1.0, 1.0).is_finite());
    }

    #[test]
    fn handles_an_inverted_domain() {
        // max below min: the span is negative, so the ratio inverts. Clamping
        // still keeps the result in range rather than producing nonsense.
        let t = normalize_domain(-50.0, 0.0, -100.0);
        assert!((0.0..=1.0).contains(&t));
    }

    #[test]
    fn clamp_unit_bounds() {
        assert_eq!(clamp_unit(-1.0), 0.0);
        assert_eq!(clamp_unit(2.0), 1.0);
        assert_eq!(clamp_unit(0.25), 0.25);
    }

    #[test]
    fn wrap_unit_matches_glsl_fract_on_positive_input() {
        assert_eq!(wrap_unit(0.25), 0.25);
        assert_eq!(wrap_unit(1.25), 0.25);
        assert_eq!(wrap_unit(3.5), 0.5);
    }

    #[test]
    fn wrap_unit_stays_positive_where_rust_fract_would_not() {
        // The whole reason this function exists: (-0.25).fract() is -0.25.
        assert_eq!((-0.25f32).fract(), -0.25);
        assert_eq!(wrap_unit(-0.25), 0.75);
        assert_eq!(wrap_unit(-1.25), 0.75);
    }

    #[test]
    fn lambert_is_full_facing_the_light() {
        assert_eq!(lambert_intensity(1.0, 0.0), 1.0);
        assert_eq!(lambert_intensity(1.0, 0.2), 1.0);
    }

    #[test]
    fn lambert_falls_to_the_ambient_floor_facing_away() {
        // Not zero: geometry facing away must stay visible against the
        // background rather than vanishing.
        assert_eq!(lambert_intensity(-1.0, 0.2), 0.2);
        assert_eq!(lambert_intensity(0.0, 0.2), 0.2);
    }

    #[test]
    fn lambert_interpolates_between_floor_and_full() {
        let mid = lambert_intensity(0.5, 0.2);
        assert!((mid - 0.6).abs() < 1.0e-5, "mid = {mid}");
    }

    #[test]
    fn lambert_is_always_in_range() {
        for n_dot_l in [-2.0, -1.0, -0.3, 0.0, 0.4, 1.0, 3.0] {
            for ambient in [0.0, 0.15, 1.0] {
                let i = lambert_intensity(n_dot_l, ambient);
                assert!(i >= 0.0 && i <= 1.0, "intensity({n_dot_l}, {ambient}) = {i}");
            }
        }
    }

    #[test]
    fn lambert_tolerates_an_out_of_range_ambient() {
        assert_eq!(lambert_intensity(0.0, 5.0), 1.0);
        assert_eq!(lambert_intensity(1.0, -1.0), 1.0);
    }

    #[test]
    fn grid_line_is_opaque_on_the_line() {
        // Exactly on an integer coordinate, coverage is full.
        assert_eq!(grid_line_alpha(0.0, 0.01, 1.0), 1.0);
        assert_eq!(grid_line_alpha(3.0, 0.01, 1.0), 1.0);
        assert_eq!(grid_line_alpha(-2.0, 0.01, 1.0), 1.0);
    }

    #[test]
    fn grid_line_is_transparent_between_lines() {
        // Halfway between gridlines, at a zoom where half a cell is many
        // pixels, coverage is zero.
        assert_eq!(grid_line_alpha(0.5, 0.01, 1.0), 0.0);
        assert_eq!(grid_line_alpha(7.5, 0.01, 1.0), 0.0);
    }

    #[test]
    fn grid_line_falls_off_over_one_pixel() {
        // derivative 0.1 grid units per pixel, thickness 2px: full coverage
        // out to half a pixel beyond the half-width, then a one-pixel ramp.
        // Tolerances rather than equality: 0.15 / 0.1 is not exactly 1.5 in
        // f32, and the wrap adds its own rounding.
        let close = |a: f32, b: f32| assert!((a - b).abs() < 1.0e-5, "{a} != {b}");

        close(grid_line_alpha(0.0, 0.1, 2.0), 1.0);
        close(grid_line_alpha(0.1, 0.1, 2.0), 0.5);
        close(grid_line_alpha(0.15, 0.1, 2.0), 0.0);
    }

    #[test]
    fn a_hairline_on_a_pixel_boundary_stays_visible() {
        // The case that motivates the box filter. Gridlines land on integer
        // coordinates, which fall on pixel boundaries, so the nearest sample
        // points sit half a pixel either side. A 1px line must put half its
        // ink on each - a naive linear ramp gives both of them zero and the
        // line vanishes.
        let derivative = 0.125;
        let half_pixel = 0.5 * derivative;

        let left = grid_line_alpha(-half_pixel, derivative, 1.0);
        let right = grid_line_alpha(half_pixel, derivative, 1.0);

        assert!((left - 0.5).abs() < 1.0e-5, "left = {left}");
        assert!((right - 0.5).abs() < 1.0e-5, "right = {right}");

        // Total ink is one pixel wide, which is what "1px line" should mean.
        assert!(((left + right) - 1.0).abs() < 1.0e-5);
    }

    #[test]
    fn total_coverage_tracks_thickness() {
        // Summing coverage across the pixels around a line should recover the
        // requested width, which is the property that makes thickness mean
        // something in pixels rather than being a vague knob.
        let derivative = 0.1;

        for thickness in [1.0, 2.0, 3.0, 4.0] {
            let total: f32 = (-8..8)
                .map(|i| {
                    let coord = (i as f32 + 0.5) * derivative;
                    grid_line_alpha(coord, derivative, thickness)
                })
                .sum();

            assert!(
                (total - thickness).abs() < 1.0e-4,
                "thickness {thickness} produced {total} pixels of ink"
            );
        }
    }

    #[test]
    fn grid_line_thickness_scales_coverage() {
        // A thicker line covers a point that a thinner one does not.
        let thin = grid_line_alpha(0.05, 0.1, 1.0);
        let thick = grid_line_alpha(0.05, 0.1, 4.0);

        assert!(thick > thin, "thick = {thick}, thin = {thin}");
    }

    #[test]
    fn grid_line_survives_a_zero_derivative() {
        // Degenerate geometry: the coordinate does not vary across the pixel.
        // Must not divide by zero.
        assert_eq!(grid_line_alpha(0.0, 0.0, 1.0), 0.0);
        assert!(grid_line_alpha(0.0, 0.0, 1.0).is_finite());
    }

    #[test]
    fn grid_line_alpha_is_always_in_range() {
        let coords = [-5.5, -1.0, -0.25, 0.0, 0.4, 1.0, 9.9];
        let derivatives = [0.001, 0.05, 0.5, 2.0];

        for c in coords {
            for d in derivatives {
                let a = grid_line_alpha(c, d, 1.5);
                assert!(a >= 0.0 && a <= 1.0, "alpha({c}, {d}) = {a}");
            }
        }
    }

    #[test]
    fn normalize2_produces_unit_length() {
        let (x, y) = normalize2(3.0, 4.0);
        assert!((x - 0.6).abs() < 1.0e-5, "x = {x}");
        assert!((y - 0.8).abs() < 1.0e-5, "y = {y}");
    }

    #[test]
    fn normalize2_survives_a_zero_length_segment() {
        // A polyline with a repeated point. Must not be NaN.
        let (x, y) = normalize2(0.0, 0.0);
        assert_eq!((x, y), (0.0, 0.0));
        assert!(x.is_finite() && y.is_finite());
    }

    #[test]
    fn normalize3_produces_unit_length() {
        let (x, y, z) = normalize3(0.0, 3.0, 4.0);
        assert!((x - 0.0).abs() < 1.0e-5);
        assert!((y - 0.6).abs() < 1.0e-5, "y = {y}");
        assert!((z - 0.8).abs() < 1.0e-5, "z = {z}");

        let length = (x * x + y * y + z * z).sqrt();
        assert!((length - 1.0).abs() < 1.0e-5);
    }

    #[test]
    fn normalize3_survives_a_zero_vector() {
        // A zero-area triangle, or a normal attribute an exporter left blank.
        let n = normalize3(0.0, 0.0, 0.0);
        assert_eq!(n, (0.0, 0.0, 0.0));
        assert!(n.0.is_finite() && n.1.is_finite() && n.2.is_finite());
    }

    #[test]
    fn normalize3_stays_finite_at_extreme_magnitudes() {
        // 1e30 squared overflows f32. Without scaling first, length_squared
        // becomes infinity, sqrt of that is NaN, and the normal is destroyed.
        for v in [
            (1.0e-30, 0.0, 0.0),
            (1.0e30, 1.0e30, 0.0),
            (3.0e38, -3.0e38, 3.0e38),
            (0.0, 0.0, -1.0),
        ] {
            let (x, y, z) = normalize3(v.0, v.1, v.2);

            assert!(
                x.is_finite() && y.is_finite() && z.is_finite(),
                "{v:?} -> ({x}, {y}, {z})"
            );

            let length = (x * x + y * y + z * z).sqrt();
            assert!((length - 1.0).abs() < 1.0e-4, "{v:?} -> length {length}");
        }
    }

    #[test]
    fn normalize2_stays_finite_at_extreme_magnitudes() {
        for v in [(1.0e30, 1.0e30), (3.0e38, -1.0e-30), (1.0e-30, 0.0)] {
            let (x, y) = normalize2(v.0, v.1);

            assert!(x.is_finite() && y.is_finite(), "{v:?} -> ({x}, {y})");

            let length = (x * x + y * y).sqrt();
            assert!((length - 1.0).abs() < 1.0e-4, "{v:?} -> length {length}");
        }
    }

    #[test]
    fn perpendicular2_is_orthogonal_and_unit() {
        let (px, py) = perpendicular2(1.0, 0.0);
        assert!((px - 0.0).abs() < 1.0e-5);
        assert!((py - 1.0).abs() < 1.0e-5);

        // Orthogonality: the dot product with the input direction is zero.
        let (dx, dy) = normalize2(2.0, -5.0);
        let (qx, qy) = perpendicular2(2.0, -5.0);
        assert!((dx * qx + dy * qy).abs() < 1.0e-5);
    }

    #[test]
    fn perpendicular2_survives_degenerate_input() {
        assert_eq!(perpendicular2(0.0, 0.0), (0.0, 0.0));
    }

    #[test]
    fn sdf_coverage_is_half_on_the_outline() {
        // The defining property: the stored 0.5 contour *is* the glyph edge,
        // at every scale.
        for range in [0.5, 1.0, 4.0, 64.0] {
            assert!((sdf_coverage(0.5, range) - 0.5).abs() < 1.0e-6);
        }
    }

    #[test]
    fn sdf_coverage_saturates_well_inside_and_outside() {
        assert_eq!(sdf_coverage(1.0, 8.0), 1.0);
        assert_eq!(sdf_coverage(0.0, 8.0), 0.0);
    }

    #[test]
    fn sdf_coverage_stays_in_range() {
        let samples = [-1.0, 0.0, 0.25, 0.5, 0.75, 1.0, 2.0];

        for d in samples {
            for range in [0.0, 0.1, 1.0, 1000.0] {
                let a = sdf_coverage(d, range);
                assert!((0.0..=1.0).contains(&a), "sdf_coverage({d}, {range}) = {a}");
            }
        }
    }

    #[test]
    fn a_larger_range_sharpens_the_edge() {
        // Same distance, further from the outline in screen terms, so closer
        // to saturation. This is what makes large text crisp and small text
        // soft from one atlas.
        let near_edge = 0.55;

        let soft = sdf_coverage(near_edge, 2.0);
        let sharp = sdf_coverage(near_edge, 20.0);

        assert!(sharp > soft, "{soft} -> {sharp}");
        assert_eq!(sharp, 1.0);
    }

    #[test]
    fn a_zero_range_is_a_hard_threshold_not_a_division() {
        // Reachable by drawing text at size zero.
        assert_eq!(sdf_coverage(0.9, 0.0), 0.5);
        assert!(sdf_coverage(0.1, 0.0).is_finite());
    }

    #[test]
    fn wrap_unit_result_is_always_in_range() {
        let samples = [-10.0, -1.5, -0.0001, 0.0, 0.5, 1.0, 7.75, 1000.5];

        for x in samples {
            let w = wrap_unit(x);
            assert!(w >= 0.0 && w < 1.0, "wrap_unit({x}) = {w} out of [0, 1)");
        }
    }
}

#[cfg(test)]
mod shape_tests {
    use super::*;

    // Distances are in pixels, so "within a hundredth of a pixel" is the
    // tolerance that matters visually rather than an arbitrary epsilon.
    fn close(a: f32, b: f32) {
        assert!((a - b).abs() < 0.01, "expected {b}, got {a}");
    }

    // ---- coverage ---------------------------------------------------------

    #[test]
    fn coverage_is_full_well_inside_and_zero_well_outside() {
        assert_eq!(shape_coverage(-5.0), 1.0);
        assert_eq!(shape_coverage(5.0), 0.0);
    }

    #[test]
    fn coverage_is_half_exactly_on_the_edge() {
        // The defining property of the box filter: a fragment centred on the
        // outline is half covered. Anything else makes hairlines wrong.
        assert_eq!(shape_coverage(0.0), 0.5);
    }

    #[test]
    fn coverage_ramps_across_exactly_one_pixel() {
        assert_eq!(shape_coverage(-0.5), 1.0);
        assert_eq!(shape_coverage(0.5), 0.0);
    }

    // ---- rounded box ------------------------------------------------------

    #[test]
    fn rounded_box_is_negative_inside_and_positive_outside() {
        assert!(rounded_box_distance(0.0, 0.0, 50.0, 20.0, 0.0) < 0.0);
        assert!(rounded_box_distance(100.0, 0.0, 50.0, 20.0, 0.0) > 0.0);
    }

    #[test]
    fn rounded_box_with_zero_radius_is_a_rectangle() {
        // On the right edge, and one pixel outside it.
        close(rounded_box_distance(50.0, 0.0, 50.0, 20.0, 0.0), 0.0);
        close(rounded_box_distance(51.0, 0.0, 50.0, 20.0, 0.0), 1.0);
        close(rounded_box_distance(49.0, 0.0, 50.0, 20.0, 0.0), -1.0);
    }

    #[test]
    fn a_square_with_half_side_radius_is_an_exact_circle() {
        // This is why there is no separate circle primitive. Points on the
        // circle of radius 25 must all be at distance zero.
        let r = 25.0;
        close(rounded_box_distance(r, 0.0, r, r, r), 0.0);
        close(rounded_box_distance(0.0, r, r, r, r), 0.0);

        // And a diagonal point at radius r, which a rectangle would place
        // well inside.
        let d = r / core::f32::consts::SQRT_2;
        close(rounded_box_distance(d, d, r, r, r), 0.0);
    }

    #[test]
    fn rounded_box_clamps_an_oversized_radius() {
        // Asking for a 500px radius on a 40px-tall box must give a stadium,
        // not an inside-out shape. Reachable from a UI slider.
        let d = rounded_box_distance(0.0, 0.0, 50.0, 20.0, 500.0);
        assert!(d < 0.0, "centre must stay inside, got {d}");
        close(d, -20.0);
    }

    #[test]
    fn rounded_box_rejects_a_negative_radius() {
        let clamped = rounded_box_distance(50.0, 0.0, 50.0, 20.0, -10.0);
        let zero = rounded_box_distance(50.0, 0.0, 50.0, 20.0, 0.0);
        close(clamped, zero);
    }

    #[test]
    fn rounded_corner_is_further_out_than_a_square_corner() {
        // The whole point of a radius: the corner is cut away, so a point at
        // the old corner is now outside.
        let square = rounded_box_distance(50.0, 20.0, 50.0, 20.0, 0.0);
        let rounded = rounded_box_distance(50.0, 20.0, 50.0, 20.0, 10.0);

        close(square, 0.0);
        assert!(rounded > 0.0, "corner should be outside, got {rounded}");
    }

    // ---- per-corner radii -------------------------------------------------

    #[test]
    fn quadrant_radius_selects_by_sign_with_y_down() {
        // Clockwise from top left, matching CSS. Negative y is up.
        assert_eq!(quadrant_radius(-1.0, -1.0, 1.0, 2.0, 3.0, 4.0), 1.0);
        assert_eq!(quadrant_radius(1.0, -1.0, 1.0, 2.0, 3.0, 4.0), 2.0);
        assert_eq!(quadrant_radius(1.0, 1.0, 1.0, 2.0, 3.0, 4.0), 3.0);
        assert_eq!(quadrant_radius(-1.0, 1.0, 1.0, 2.0, 3.0, 4.0), 4.0);
    }

    // ---- ellipse ----------------------------------------------------------

    #[test]
    fn ellipse_is_exact_on_its_axes() {
        // The approximation's error is zero on the axes, so these are equalities
        // in spirit even at a tight tolerance.
        close(ellipse_distance(40.0, 0.0, 40.0, 20.0), 0.0);
        close(ellipse_distance(0.0, 20.0, 40.0, 20.0), 0.0);
        close(ellipse_distance(41.0, 0.0, 40.0, 20.0), 1.0);
    }

    #[test]
    fn ellipse_centre_is_the_shorter_radius_inside() {
        close(ellipse_distance(0.0, 0.0, 40.0, 20.0), -20.0);
    }

    #[test]
    fn ellipse_with_a_collapsed_radius_does_not_produce_nan() {
        // Reachable by animating a width to zero.
        let d = ellipse_distance(10.0, 0.0, 0.0, 20.0);
        assert!(d.is_finite(), "got {d}");
        assert!(d >= 0.0);
    }

    #[test]
    fn a_circular_ellipse_matches_a_circle() {
        for (x, y) in [(30.0, 0.0), (0.0, 30.0), (21.213, 21.213)] {
            close(ellipse_distance(x, y, 30.0, 30.0), 0.0);
        }
    }

    // ---- pie --------------------------------------------------------------

    // A quarter turn each side of +Y, i.e. the whole upper half plane.
    fn quarter() -> (f32, f32) {
        let half = core::f32::consts::FRAC_PI_4;
        (half.sin(), half.cos())
    }

    #[test]
    fn pie_contains_points_inside_its_wedge() {
        let (s, c) = quarter();
        assert!(pie_distance(0.0, 30.0, s, c, 50.0) < 0.0);
    }

    #[test]
    fn pie_excludes_points_outside_its_wedge() {
        let (s, c) = quarter();
        // Directly opposite the opening.
        assert!(pie_distance(0.0, -30.0, s, c, 50.0) > 0.0);
    }

    #[test]
    fn pie_excludes_points_beyond_its_radius() {
        let (s, c) = quarter();
        assert!(pie_distance(0.0, 80.0, s, c, 50.0) > 0.0);
        close(pie_distance(0.0, 50.0, s, c, 50.0), 0.0);
    }

    #[test]
    fn pie_is_symmetric_about_its_axis() {
        let (s, c) = quarter();
        let left = pie_distance(-20.0, 30.0, s, c, 50.0);
        let right = pie_distance(20.0, 30.0, s, c, 50.0);
        close(left, right);
    }

    // ---- arc --------------------------------------------------------------

    #[test]
    fn arc_is_a_band_around_its_centreline() {
        let (s, c) = quarter();
        // On the centreline at radius 40, band half-thickness 5.
        close(arc_distance(0.0, 40.0, s, c, 40.0, 5.0), -5.0);
        // At the inner and outer edges.
        close(arc_distance(0.0, 35.0, s, c, 40.0, 5.0), 0.0);
        close(arc_distance(0.0, 45.0, s, c, 40.0, 5.0), 0.0);
    }

    #[test]
    fn arc_is_hollow_at_the_centre() {
        // The distinction from a pie: the middle is not filled.
        let (s, c) = quarter();
        assert!(arc_distance(0.0, 0.0, s, c, 40.0, 5.0) > 0.0);
    }

    #[test]
    fn arc_ends_are_capped_not_infinite() {
        let (s, c) = quarter();
        // Well outside the angular span, at the centreline radius.
        assert!(arc_distance(0.0, -40.0, s, c, 40.0, 5.0) > 0.0);
    }

    // ---- rotation ---------------------------------------------------------

    #[test]
    fn rotate2_by_a_quarter_turn() {
        let (c, s) = (0.0, 1.0); // cos 90, sin 90
        let (x, y) = rotate2(1.0, 0.0, c, s);
        close(x, 0.0);
        close(y, 1.0);
    }

    #[test]
    fn rotate2_preserves_length() {
        let angle: f32 = 0.7;
        let (x, y) = rotate2(3.0, 4.0, angle.cos(), angle.sin());
        close((x * x + y * y).sqrt(), 5.0);
    }

    // ---- gradients --------------------------------------------------------

    #[test]
    fn linear_gradient_runs_from_zero_to_one_along_its_axis() {
        assert_eq!(linear_gradient_t(0.0, 0.0, 0.0, 0.0, 100.0, 0.0), 0.0);
        assert_eq!(linear_gradient_t(100.0, 0.0, 0.0, 0.0, 100.0, 0.0), 1.0);
        close(linear_gradient_t(50.0, 0.0, 0.0, 0.0, 100.0, 0.0), 0.5);
    }

    #[test]
    fn linear_gradient_clamps_beyond_its_endpoints() {
        assert_eq!(linear_gradient_t(-50.0, 0.0, 0.0, 0.0, 100.0, 0.0), 0.0);
        assert_eq!(linear_gradient_t(150.0, 0.0, 0.0, 0.0, 100.0, 0.0), 1.0);
    }

    #[test]
    fn linear_gradient_ignores_the_perpendicular_offset() {
        // A point off the axis projects onto it; the gradient has no width.
        close(
            linear_gradient_t(50.0, 999.0, 0.0, 0.0, 100.0, 0.0),
            linear_gradient_t(50.0, 0.0, 0.0, 0.0, 100.0, 0.0),
        );
    }

    #[test]
    fn a_collapsed_linear_gradient_does_not_divide_by_zero() {
        let t = linear_gradient_t(10.0, 10.0, 5.0, 5.0, 5.0, 5.0);
        assert!(t.is_finite());
        assert_eq!(t, 0.0);
    }

    #[test]
    fn radial_gradient_runs_from_centre_to_rim() {
        assert_eq!(radial_gradient_t(0.0, 0.0, 0.0, 0.0, 50.0), 0.0);
        assert_eq!(radial_gradient_t(50.0, 0.0, 0.0, 0.0, 50.0), 1.0);
        close(radial_gradient_t(25.0, 0.0, 0.0, 0.0, 50.0), 0.5);
    }

    #[test]
    fn a_collapsed_radial_gradient_reads_as_its_outer_colour() {
        assert_eq!(radial_gradient_t(0.0, 0.0, 0.0, 0.0, 0.0), 1.0);
    }

    // ---- stroke -----------------------------------------------------------

    #[test]
    fn stroke_band_straddles_the_outline() {
        // Fill distance zero means on the outline, which is the centre of the
        // stroke band and therefore fully covered.
        close(stroke_distance(0.0, 2.0), -2.0);
        // Half a band width either side is the band's own edge.
        close(stroke_distance(2.0, 2.0), 0.0);
        close(stroke_distance(-2.0, 2.0), 0.0);
    }

    #[test]
    fn stroke_is_symmetric_across_the_outline() {
        close(stroke_distance(3.0, 2.0), stroke_distance(-3.0, 2.0));
    }
}
