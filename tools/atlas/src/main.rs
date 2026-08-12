//! Bakes a signed distance field font atlas.
//!
//! A maintainer tool, in the same sense as `cargo-gpu` and `naga`: its output
//! is committed under `priv/fonts/`, and nothing that consumes wx_mvu ever
//! runs it. That is the same boundary the shader pipeline draws, for the same
//! reason — getting a glyph outline into a texture needs a font rasterizer,
//! and requiring one at `mix deps.get` time would make Rust a consumer
//! dependency by the back door.
//!
//! Stable Rust, and deliberately so: this must never acquire the shader
//! nightly.
//!
//!     cargo run --release -- \
//!         --font ../../fonts/dejavu/DejaVuSans.ttf \
//!         --out ../../fonts/out \
//!         --name dejavu-sans \
//!         --size 48 --range 6 --padding 6 --width 512
//!
//! Writes `<name>.r8` (raw single-channel atlas, no container format, so the
//! Elixir side needs no image decoder) and `<name>.json` (metrics).

use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

use fontdue::{Font, FontSettings};

/// Stand-in for infinity in the distance transform.
///
/// The Felzenszwalb algorithm computes the intersection of two parabolas as a
/// difference over a difference; with true infinities that is `inf - inf`,
/// which is NaN, and a NaN comparison silently takes the wrong branch. A large
/// finite value keeps every comparison meaningful.
const FAR: f64 = 1.0e20;

struct Args {
    font: PathBuf,
    out: PathBuf,
    name: String,
    size: f32,
    range: f32,
    padding: u32,
    width: u32,
    chars: String,
}

fn parse_args() -> Args {
    let mut font = None;
    let mut out = PathBuf::from(".");
    let mut name = String::from("font");
    let mut size = 48.0f32;
    let mut range = 6.0f32;
    let mut padding = 6u32;
    let mut width = 512u32;
    let mut chars: String = (32u8..127).map(|c| c as char).collect();

    let mut argv = std::env::args().skip(1);
    while let Some(flag) = argv.next() {
        let mut value = || argv.next().unwrap_or_else(|| panic!("{flag} needs a value"));

        match flag.as_str() {
            "--font" => font = Some(PathBuf::from(value())),
            "--out" => out = PathBuf::from(value()),
            "--name" => name = value(),
            "--size" => size = value().parse().expect("--size"),
            "--range" => range = value().parse().expect("--range"),
            "--padding" => padding = value().parse().expect("--padding"),
            "--width" => width = value().parse().expect("--width"),
            "--chars" => chars = value(),
            "--extra" => chars.push_str(&value()),
            other => panic!("unknown flag {other}"),
        }
    }

    Args {
        font: font.expect("--font is required"),
        out,
        name,
        size,
        range,
        padding,
        width,
        chars,
    }
}

struct Placed {
    ch: char,
    /// Region in the atlas, including padding.
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    /// Quad relative to the pen position on the baseline, y down, in baked
    /// pixels. Includes the padding, because the distance field extends into
    /// it and cropping the quad to the ink would clip the antialiased edge.
    left: f32,
    top: f32,
    advance: f32,
}

fn main() {
    let args = parse_args();

    let data = fs::read(&args.font).expect("reading the font file");
    let font = Font::from_bytes(data.as_slice(), FontSettings::default()).expect("parsing the font");

    // ----------------------------------------------------------------------
    // Rasterize, and shelf-pack into a fixed-width atlas.
    // ----------------------------------------------------------------------

    let mut coverage = vec![0u8; (args.width * args.width) as usize];
    let mut placed: Vec<Placed> = Vec::new();

    let pad = args.padding;
    let mut pen_x = pad;
    let mut pen_y = pad;
    let mut shelf_height = 0u32;
    let mut used_height = 0u32;

    for ch in args.chars.chars() {
        let (metrics, bitmap) = font.rasterize(ch, args.size);

        // A space has an advance and no ink. Giving it a cell would cost an
        // all-padding region in the atlas and six vertices per space at draw
        // time, to render nothing. A zero-sized entry carries the advance and
        // is skipped by the layout.
        if metrics.width == 0 || metrics.height == 0 {
            placed.push(Placed {
                ch,
                x: 0,
                y: 0,
                w: 0,
                h: 0,
                left: 0.0,
                top: 0.0,
                advance: metrics.advance_width,
            });
            continue;
        }

        let w = metrics.width as u32 + pad * 2;
        let h = metrics.height as u32 + pad * 2;

        if pen_x + w + pad > args.width {
            pen_x = pad;
            pen_y += shelf_height + pad;
            shelf_height = 0;
        }

        if pen_y + h + pad > args.width {
            panic!(
                "atlas is too small: {}x{} ran out at '{ch}'. Raise --width or lower --size.",
                args.width, args.width
            );
        }

        for row in 0..metrics.height {
            for col in 0..metrics.width {
                let dst = (pen_y + pad + row as u32) * args.width + pen_x + pad + col as u32;
                coverage[dst as usize] = bitmap[row * metrics.width + col];
            }
        }

        placed.push(Placed {
            ch,
            x: pen_x,
            y: pen_y,
            w,
            h,
            // fontdue's ymin is the offset of the bitmap's *bottom* above the
            // baseline, with y up. Text layout wants the quad's top, y down.
            left: metrics.xmin as f32 - pad as f32,
            top: -(metrics.ymin as f32 + metrics.height as f32) - pad as f32,
            advance: metrics.advance_width,
        });

        pen_x += w + pad;
        shelf_height = shelf_height.max(h);
        used_height = used_height.max(pen_y + h + pad);
    }

    // Trim to the rows actually used, rounded up to a multiple of 4 so the
    // unpack alignment GL defaults to is never violated.
    let height = ((used_height + 3) / 4) * 4;
    coverage.truncate((args.width * height) as usize);

    // ----------------------------------------------------------------------
    // Coverage -> signed distance field.
    // ----------------------------------------------------------------------

    let field = signed_distance_field(&coverage, args.width, height, args.range);

    // ----------------------------------------------------------------------
    // Metrics.
    // ----------------------------------------------------------------------

    let line_metrics = font
        .horizontal_line_metrics(args.size)
        .expect("the font has no horizontal line metrics");

    let mut kerning: BTreeMap<String, f32> = BTreeMap::new();
    for a in args.chars.chars() {
        for b in args.chars.chars() {
            if let Some(k) = font.horizontal_kern(a, b, args.size) {
                if k != 0.0 {
                    kerning.insert(format!("{}:{}", a as u32, b as u32), k);
                }
            }
        }
    }

    fs::create_dir_all(&args.out).expect("creating the output directory");

    let raw = args.out.join(format!("{}.r8", args.name));
    fs::write(&raw, &field).expect("writing the atlas");

    let json = args.out.join(format!("{}.json", args.name));
    fs::write(&json, metrics_json(&args, &placed, &line_metrics, &kerning, height))
        .expect("writing the metrics");

    eprintln!(
        "{}: {} glyphs, {}x{} atlas, {} bytes",
        args.name,
        placed.len(),
        args.width,
        height,
        field.len()
    );
}

/// Squared Euclidean distance transform, Felzenszwalb & Huttenlocher 2012.
///
/// Linear time per row and per column, which matters less for a 512x512 atlas
/// than the fact that it is *exact* — the cheap alternatives (chamfer masks,
/// 8SSEDT) accumulate error along diagonals, and a distance field's whole job
/// is to be metrically correct away from the seeds.
fn edt_1d(f: &[f64]) -> Vec<f64> {
    let n = f.len();
    let mut d = vec![0.0; n];
    let mut v = vec![0usize; n];
    let mut z = vec![0.0f64; n + 1];

    let mut k = 0usize;
    v[0] = 0;
    z[0] = -FAR;
    z[1] = FAR;

    for q in 1..n {
        loop {
            let vk = v[k] as f64;
            let qf = q as f64;
            let s = ((f[q] + qf * qf) - (f[v[k]] + vk * vk)) / (2.0 * qf - 2.0 * vk);

            if s <= z[k] && k > 0 {
                k -= 1;
            } else {
                k += 1;
                v[k] = q;
                z[k] = s;
                z[k + 1] = FAR;
                break;
            }
        }
    }

    k = 0;
    for q in 0..n {
        while z[k + 1] < q as f64 {
            k += 1;
        }
        let dq = q as f64 - v[k] as f64;
        d[q] = dq * dq + f[v[k]];
    }

    d
}

fn distance_to_seeds(seed: &[bool], width: u32, height: u32) -> Vec<f64> {
    let (w, h) = (width as usize, height as usize);
    let mut grid: Vec<f64> = seed.iter().map(|&s| if s { 0.0 } else { FAR }).collect();

    for y in 0..h {
        let row: Vec<f64> = grid[y * w..(y + 1) * w].to_vec();
        let d = edt_1d(&row);
        grid[y * w..(y + 1) * w].copy_from_slice(&d);
    }

    for x in 0..w {
        let column: Vec<f64> = (0..h).map(|y| grid[y * w + x]).collect();
        let d = edt_1d(&column);
        for y in 0..h {
            grid[y * w + x] = d[y];
        }
    }

    grid.iter().map(|v| v.sqrt()).collect()
}

/// Signed distance, encoded so that `0.5` is the outline and the full byte
/// range spans `±range` pixels.
///
/// The sign convention — inside above 0.5 — is what `sdf_coverage` in
/// `wx-mvu-shader-core` assumes, and the two must agree or every glyph renders
/// as its own hole.
fn signed_distance_field(coverage: &[u8], width: u32, height: u32, range: f32) -> Vec<u8> {
    let inside: Vec<bool> = coverage.iter().map(|&c| c >= 128).collect();
    let outside: Vec<bool> = inside.iter().map(|&i| !i).collect();

    // Distance from every pixel to the nearest pixel of the opposite class.
    let to_inside = distance_to_seeds(&inside, width, height);
    let to_outside = distance_to_seeds(&outside, width, height);

    inside
        .iter()
        .enumerate()
        .map(|(i, &is_inside)| {
            // Half a pixel off each, so the boundary between an inside and an
            // outside pixel sits *between* them rather than on one of them.
            let signed = if is_inside {
                to_outside[i] - 0.5
            } else {
                -(to_inside[i] - 0.5)
            };

            let t = 0.5 + signed / (2.0 * range as f64);
            (t.clamp(0.0, 1.0) * 255.0).round() as u8
        })
        .collect()
}

fn metrics_json(
    args: &Args,
    placed: &[Placed],
    line: &fontdue::LineMetrics,
    kerning: &BTreeMap<String, f32>,
    height: u32,
) -> String {
    let mut out = String::new();
    out.push_str("{\n");
    out.push_str(&format!("  \"name\": \"{}\",\n", args.name));
    out.push_str(&format!("  \"size\": {},\n", args.size));
    out.push_str(&format!("  \"range\": {},\n", args.range));
    out.push_str(&format!("  \"atlas_width\": {},\n", args.width));
    out.push_str(&format!("  \"atlas_height\": {},\n", height));
    out.push_str(&format!("  \"ascent\": {},\n", line.ascent));
    out.push_str(&format!("  \"descent\": {},\n", line.descent));
    out.push_str(&format!(
        "  \"line_height\": {},\n",
        line.ascent - line.descent + line.line_gap
    ));

    out.push_str("  \"glyphs\": [\n");
    let entries: Vec<String> = placed
        .iter()
        .map(|g| {
            format!(
                "    {{\"codepoint\": {}, \"x\": {}, \"y\": {}, \"w\": {}, \"h\": {}, \
                 \"left\": {}, \"top\": {}, \"advance\": {}}}",
                g.ch as u32, g.x, g.y, g.w, g.h, g.left, g.top, g.advance
            )
        })
        .collect();
    out.push_str(&entries.join(",\n"));
    out.push_str("\n  ],\n");

    out.push_str("  \"kerning\": {\n");
    let kerns: Vec<String> = kerning
        .iter()
        .map(|(pair, k)| format!("    \"{pair}\": {k}"))
        .collect();
    out.push_str(&kerns.join(",\n"));
    out.push_str("\n  }\n}\n");

    out
}
