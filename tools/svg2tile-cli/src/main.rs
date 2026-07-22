use clap::Parser;
use image::{codecs::gif::GifEncoder, Delay, Frame, RgbaImage};
use resvg::usvg::{Options, Tree, Transform};
use resvg::tiny_skia::Pixmap;
use std::{fs, path::PathBuf, time::Duration};

mod render;
mod tile;
use render::render_svg_to_pixmap;
use tile::render_via_tile;

#[derive(Parser)]
#[command(name = "svg2tile-cli")]
#[command(about = "Render SVG to PNG (static) or GIF (animated) using tile server or resvg directly")]
struct Args {
    /// Input SVG file
    input: PathBuf,

    /// Output file (PNG or GIF)
    #[arg(short, long)]
    output: Option<PathBuf>,

    /// Path to resvg-render tile .so (loads via libloading)
    #[arg(long)]
    tile: Option<PathBuf>,

    /// Frame rate for animated GIF
    #[arg(short, long, default_value_t = 10)]
    fps: u32,

    /// Output width in pixels
    #[arg(short = 'W', long)]
    width: Option<u32>,

    /// Output height in pixels
    #[arg(short = 'H', long)]
    height: Option<u32>,
}

fn main() {
    env_logger::init();
    let args = Args::parse();
    let svg_data = fs::read(&args.input).expect("read svg");

    let output = args.output.clone().unwrap_or_else(|| {
        let stem = args.input.file_stem().unwrap_or_default().to_string_lossy();
        if has_animation(&svg_data) {
            PathBuf::from(format!("{}.gif", stem))
        } else {
            PathBuf::from(format!("{}.png", stem))
        }
    });

    if has_animation(&svg_data) {
        render_animated(&args, &svg_data, &output);
    } else {
        render_static(&args, &svg_data, &output);
    }
}

fn has_animation(data: &[u8]) -> bool {
    let s = String::from_utf8_lossy(data);
    s.contains("<animate")
        || s.contains("<animateTransform")
        || s.contains("<animateMotion")
        || s.contains("<set>")
        || s.contains("<script")
        || s.contains("javascript:")
}

fn render_static(args: &Args, svg_data: &[u8], output: &PathBuf) {
    if let Some(ref tile_path) = args.tile {
        match render_via_tile(tile_path, svg_data) {
            Ok(png_bytes) => {
                fs::write(output, png_bytes).expect("write png");
                eprintln!("OK: {} -> {}", args.input.display(), output.display());
            }
            Err(e) => {
                eprintln!("Tile render failed: {}, falling back to resvg", e);
                let (w, h, pixmap) = render_svg_to_pixmap(svg_data, args.width, args.height)
                    .expect("render svg");
                let png_bytes = pixmap.encode_png().expect("encode png");
                fs::write(output, png_bytes).expect("write png");
                eprintln!("OK: {} -> {} ({}x{} via resvg)", args.input.display(), output.display(), w, h);
            }
        }
    } else {
        let (w, h, pixmap) = render_svg_to_pixmap(svg_data, args.width, args.height)
            .expect("render svg");
        let png_bytes = pixmap.encode_png().expect("encode png");
        fs::write(output, png_bytes).expect("write png");
        eprintln!("OK: {} -> {} ({}x{} via resvg)", args.input.display(), output.display(), w, h);
    }
}

fn render_animated(_args: &Args, svg_data: &[u8], output: &PathBuf) {
    let doc = xmltree::Element::parse(svg_data).expect("parse svg");

    let (w, h) = resolve_size(&doc, _args.width, _args.height);
    let anims = extract_animations(&doc);
    let max_dur = anims.iter().map(|a| a.dur).fold(0.0, f64::max);
    let total_frames = (max_dur * _args.fps as f64).ceil().max(1.0) as u32;
    let delay_ms = (1000.0 / _args.fps as f64) as u16;

    eprintln!(
        "Rendering {} frames at {}x{}, {} fps, {:.1}s total",
        total_frames, w, h, _args.fps, max_dur
    );

    let mut frames = Vec::with_capacity(total_frames as usize);
    for i in 0..total_frames {
        let t = i as f64 / _args.fps as f64;
        let frame_svg = bake_frame(&doc, &anims, t);
        let img = render_svg_to_pixmap(frame_svg.as_bytes(), Some(w), Some(h))
            .expect("render frame")
            .2;
        frames.push(RgbaImage::from_raw(w, h, img.data().to_vec()).expect("image"));
    }

    let file = fs::File::create(output).expect("create output");
    let mut encoder = GifEncoder::new(file);
    encoder.set_repeat(image::codecs::gif::Repeat::Infinite).expect("set repeat");
    let delay = Delay::from_saturating_duration(Duration::from_millis(delay_ms as u64));
    for img in &frames {
        encoder.encode_frame(Frame::from_parts(img.clone(), 0, 0, delay)).expect("encode frame");
    }
    eprintln!("OK: {} -> {} ({} frames)", _args.input.display(), output.display(), frames.len());
}

mod anim {
    use super::*;

    #[derive(Debug, Clone)]
    pub(crate) struct AnimInfo {
        pub(crate) attr_name: String,
        pub(crate) values: Vec<String>,
        pub(crate) key_times: Vec<f64>,
        pub(crate) dur: f64,
        pub(crate) calc_mode: CalcMode,
        pub(crate) transform_type: TransformType,
        pub(crate) from: Option<String>,
        pub(crate) to: Option<String>,
    }

    #[derive(Debug, Clone, Copy, PartialEq)]
    pub(crate) enum CalcMode {
        Linear,
        Discrete,
    }

    #[derive(Debug, Clone, Copy, PartialEq)]
    pub(crate) enum TransformType {
        None,
        Rotate,
    }

    pub(crate) fn extract_animations(doc: &xmltree::Element) -> Vec<AnimInfo> {
        let mut anims = Vec::new();
        collect_animations(doc, &mut anims);
        anims
    }

    fn collect_animations(element: &xmltree::Element, anims: &mut Vec<AnimInfo>) {
        for child in &element.children {
            if let xmltree::XMLNode::Element(e) = child {
                let tag = &e.name;
                if tag == "animate" || tag == "animateTransform" {
                    let attr_name = e
                        .attributes
                        .get("attributeName")
                        .map(|s| s.as_str())
                        .unwrap_or("")
                        .to_string();
                    if attr_name.is_empty() {
                        continue;
                    }
                    let values = e
                        .attributes
                        .get("values")
                        .map(|v| v.split(';').map(|s| s.to_string()).collect())
                        .unwrap_or_default();
                    let key_times = e
                        .attributes
                        .get("keyTimes")
                        .map(|v| v.split(';').filter_map(|s| s.parse().ok()).collect())
                        .unwrap_or_default();
                    let dur_str = e.attributes.get("dur").map(|s| s.as_str()).unwrap_or("0s");
                    let dur = parse_dur(dur_str);
                    let calc_mode = match e
                        .attributes
                        .get("calcMode")
                        .map(|s| s.as_str())
                        .unwrap_or("linear")
                    {
                        "discrete" => CalcMode::Discrete,
                        _ => CalcMode::Linear,
                    };
                    let transform_type = if tag == "animateTransform" {
                        match e.attributes.get("type").map(|s| s.as_str()).unwrap_or("") {
                            "rotate" => TransformType::Rotate,
                            _ => TransformType::None,
                        }
                    } else {
                        TransformType::None
                    };
                    let from = e.attributes.get("from").map(|s| s.as_str().to_string());
                    let to = e.attributes.get("to").map(|s| s.as_str().to_string());

                    anims.push(AnimInfo {
                        attr_name,
                        values,
                        key_times,
                        dur,
                        calc_mode,
                        transform_type,
                        from,
                        to,
                    });
                }
                collect_animations(e, anims);
            }
        }
    }

    pub(crate) fn parse_dur(s: &str) -> f64 {
        if s.ends_with("ms") {
            s.trim_end_matches("ms").parse().unwrap_or(0.0) / 1000.0
        } else if s.ends_with('s') {
            s.trim_end_matches('s').parse().unwrap_or(0.0)
        } else {
            s.parse().unwrap_or(0.0)
        }
    }

    pub(crate) fn bake_frame(doc: &xmltree::Element, anims: &[AnimInfo], t: f64) -> String {
        let mut doc = doc.clone();
        apply_animations(&mut doc, anims, t);
        let mut buf = Vec::new();
        doc.write(&mut buf).expect("serialize");
        String::from_utf8(buf).expect("utf8")
    }

    fn apply_animations(element: &mut xmltree::Element, anims: &[AnimInfo], t: f64) {
        let children: Vec<_> = element.children.iter_mut().collect();
        for child in children {
            if let xmltree::XMLNode::Element(e) = child {
                apply_animations(e, anims, t);
            }
        }

        let mut my_anims: Vec<&AnimInfo> = Vec::new();
        for anim in anims {
            for child in &element.children {
                if let xmltree::XMLNode::Element(e) = child {
                    if e.name == "animate" || e.name == "animateTransform" {
                        let attr_name = e
                            .attributes
                            .get("attributeName")
                            .map(|s| s.as_str())
                            .unwrap_or("");
                        if attr_name == anim.attr_name {
                            my_anims.push(anim);
                        }
                    }
                }
            }
        }

        if my_anims.is_empty() {
            return;
        }

        let mut final_values: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();
        for anim in &my_anims {
            let t_mod = if anim.dur > 0.0 { t % anim.dur } else { 0.0 };
            let t_norm = if anim.dur > 0.0 { t_mod / anim.dur } else { 0.0 };
            let value = evaluate_animation(anim, t_norm);
            final_values.insert(anim.attr_name.clone(), value);
        }

        for (attr, value) in final_values {
            element.attributes.insert(attr, value);
        }

        element.children.retain(|child| {
            !matches!(child, xmltree::XMLNode::Element(e) if e.name == "animate" || e.name == "animateTransform")
        });
    }

    fn evaluate_animation(anim: &AnimInfo, t_norm: f64) -> String {
        if anim.values.is_empty() {
            return anim.from.clone().unwrap_or_default();
        }

        match anim.calc_mode {
            CalcMode::Discrete => {
                for i in 1..anim.key_times.len() {
                    if t_norm <= anim.key_times[i] {
                        return anim.values[i - 1].clone();
                    }
                }
                anim.values.last().cloned().unwrap_or_default()
            }
            CalcMode::Linear => {
                for i in 1..anim.key_times.len() {
                    if t_norm <= anim.key_times[i] {
                        let t0 = anim.key_times[i - 1];
                        let t1 = anim.key_times[i];
                        let v0 = anim.values[i - 1].parse::<f64>().unwrap_or(0.0);
                        let v1 = anim.values[i].parse::<f64>().unwrap_or(0.0);
                        if (t1 - t0).abs() < 1e-9 {
                            return format!("{:.3}", v0);
                        }
                        let frac = (t_norm - t0) / (t1 - t0);
                        let v = v0 + (v1 - v0) * frac;
                        return format!("{:.3}", v);
                    }
                }
                anim.values.last().cloned().unwrap_or_default()
            }
        }
    }
}

fn resolve_size(
    doc: &xmltree::Element,
    width: Option<u32>,
    height: Option<u32>,
) -> (u32, u32) {
    let svg_width = doc.attributes.get("width").and_then(|v| v.parse().ok());
    let svg_height = doc.attributes.get("height").and_then(|v| v.parse().ok());
    let view_box = doc.attributes.get("viewBox").and_then(|v| {
        let parts: Vec<&str> = v.split_whitespace().collect();
        if parts.len() == 4 {
            let w: Option<u32> = parts[2].parse().ok();
            let h: Option<u32> = parts[3].parse().ok();
            w.zip(h)
        } else {
            None
        }
    });

    match (width, height, svg_width, svg_height, view_box) {
        (Some(w), Some(h), _, _, _) => (w, h),
        (None, None, Some(w), Some(h), _) => (w, h),
        (None, None, None, None, Some((_, h))) => (800, h),
        _ => (800, 600),
    }
}

fn bake_frame(doc: &xmltree::Element, anims: &[anim::AnimInfo], t: f64) -> String {
    anim::bake_frame(doc, anims, t)
}

fn extract_animations(doc: &xmltree::Element) -> Vec<anim::AnimInfo> {
    anim::extract_animations(doc)
}
