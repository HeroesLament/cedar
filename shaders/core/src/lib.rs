//! Shader math shared across wx_mvu's shaders.
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
//! `mix wx_mvu.shaders.test` runs this crate on stable specifically to catch a
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
    let length_squared = x * x + y * y;

    if length_squared <= 0.0 {
        (0.0, 0.0)
    } else {
        let inverse = 1.0 / sqrt_f32(length_squared);
        (x * inverse, y * inverse)
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
    fn wrap_unit_result_is_always_in_range() {
        let samples = [-10.0, -1.5, -0.0001, 0.0, 0.5, 1.0, 7.75, 1000.5];

        for x in samples {
            let w = wrap_unit(x);
            assert!(w >= 0.0 && w < 1.0, "wrap_unit({x}) = {w} out of [0, 1)");
        }
    }
}
