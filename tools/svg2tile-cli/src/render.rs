use resvg::tiny_skia::Pixmap;
use resvg::usvg::{Options, Transform, Tree};

pub fn render_svg_to_pixmap(
    svg_data: &[u8],
    width: Option<u32>,
    height: Option<u32>,
) -> Result<(u32, u32, Pixmap), Box<dyn std::error::Error>> {
    let mut opt = Options::default();
    opt.fontdb_mut().load_system_fonts();
    let tree = Tree::from_data(svg_data, &opt)?;
    let sz = tree.size();

    let (w, h) = match (width, height) {
        (Some(w), Some(h)) => (w, h),
        (None, None) => (sz.width().ceil() as u32, sz.height().ceil() as u32),
        (Some(w), None) => (w, (sz.height() * w as f32 / sz.width()).ceil() as u32),
        (None, Some(h)) => ((sz.width() * h as f32 / sz.height()).ceil() as u32, h),
    };

    let mut pixmap = Pixmap::new(w, h).ok_or("failed to allocate pixmap")?;
    let scale = (w as f32 / sz.width() as f32).min(h as f32 / sz.height() as f32);
    let transform = Transform::from_scale(scale, scale);
    resvg::render(&tree, transform, &mut pixmap.as_mut());

    Ok((w, h, pixmap))
}
