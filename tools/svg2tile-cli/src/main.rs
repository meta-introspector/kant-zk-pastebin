use clap::Parser;
use std::{fs, path::PathBuf, time::Duration};

mod anim;
mod render;
use render::render_svg_to_pixmap;

use image::{codecs::gif::GifEncoder, Delay, Frame, RgbaImage};

#[derive(clap::Parser)]
#[command(name = "svg2tile-cli")]
#[command(about = "Render SVG to PNG (static) or GIF (animated) via resvg")]
struct Args {
    /// Input SVG file
    input: PathBuf,

    /// Output file (PNG or GIF)
    #[arg(short, long)]
    output: Option<PathBuf>,

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
    let (w, h, _pixmap) =
        render_svg_to_pixmap(svg_data, args.width, args.height).expect("render svg");
    let png_bytes = _pixmap.encode_png().expect("encode png");
    fs::write(output, png_bytes).expect("write png");
    eprintln!(
        "OK: {} -> {} ({}x{} via resvg)",
        args.input.display(),
        output.display(),
        w,
        h
    );
}

fn render_animated(_args: &Args, svg_data: &[u8], output: &PathBuf) {
    let doc = xmltree::Element::parse(svg_data).expect("parse svg");

    let (w, h) = anim::resolve_size(&doc, _args.width, _args.height);
    let anims = anim::extract_animations(&doc);
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
        let frame_svg = anim::bake_frame(&doc, &anims, t);
        let (fw, fh, pixmap) =
            render_svg_to_pixmap(frame_svg.as_bytes(), Some(w), Some(h)).expect("render frame");
        let rgba = pixmap.data();
        let img = RgbaImage::from_raw(fw, fh, rgba.to_vec()).expect("image");
        frames.push(img);
    }

    let file = fs::File::create(output).expect("create output");
    let mut encoder = GifEncoder::new(file);
    encoder
        .set_repeat(image::codecs::gif::Repeat::Infinite)
        .expect("set repeat");
    let delay = Delay::from_saturating_duration(Duration::from_millis(delay_ms as u64));
    for img in &frames {
        encoder
            .encode_frame(Frame::from_parts(img.clone(), 0, 0, delay))
            .expect("encode frame");
    }
    eprintln!(
        "OK: {} -> {} ({} frames)",
        _args.input.display(),
        output.display(),
        frames.len()
    );
}
