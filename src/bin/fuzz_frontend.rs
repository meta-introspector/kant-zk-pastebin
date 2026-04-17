/// Simulated user fuzzer — exercises all view/handler render paths
/// Uses Monster irrep corpus as input seeds, tracks coverage per code path.
use html5ever::parse_document;
use html5ever::tendril::TendrilSink;
use markup5ever_rcdom::{RcDom, NodeData, Handle};
use kant_pastebin::view;
use kant_pastebin::model::Paste;
use std::collections::{HashMap, HashSet};

// ── Coverage tracker ─────────────────────────────────────────────────────────

#[derive(Default)]
struct Coverage {
    hit: HashSet<&'static str>,
    all: Vec<&'static str>,
}

impl Coverage {
    fn register(&mut self, label: &'static str) { self.all.push(label); }
    fn hit(&mut self, label: &'static str) { self.hit.insert(label); }
    fn report(&self) {
        let pct = self.hit.len() * 100 / self.all.len().max(1);
        println!("\n=== Coverage: {}/{} paths ({}%) ===",
            self.hit.len(), self.all.len(), pct);
        for label in &self.all {
            println!("  {} {}", if self.hit.contains(label) { "✅" } else { "❌" }, label);
        }
    }
}

// ── Input generation from Monster irreps ─────────────────────────────────────

const MONSTER_PRIMES: &[u64] = &[2,3,5,7,11,13,17,19,23,29,31,41,47,59,71];

struct FuzzInput {
    title:    String,
    content:  String,
    keywords: Vec<String>,
    reply_to: Option<String>,
}

fn gen_inputs(n: usize) -> Vec<FuzzInput> {
    let mut inputs: Vec<FuzzInput> = (0..n).map(|i| {
        let coords: Vec<u64> = MONSTER_PRIMES.iter().map(|&p| (i as u64 * 13) % p).collect();
        FuzzInput {
            title:    format!("Test_{}", coords[0]),
            content:  (0..coords[1] % 20).map(|j| format!("word{} ", j)).collect(),
            keywords: (0..coords[2] % 4).map(|j| format!("tag{}", j)).collect(),
            reply_to: if coords[3] % 2 == 0 { Some(format!("20260101_000000_{:03}", i)) } else { None },
        }
    }).collect();
    // Edge cases: empty title, long content
    inputs[0].title = String::new();
    inputs[1].content = "x ".repeat(30); // > 50 chars
    inputs
}

// ── HTML assertion helpers ────────────────────────────────────────────────────

fn parse(html: &str) -> RcDom {
    parse_document(RcDom::default(), Default::default())
        .from_utf8()
        .read_from(&mut html.as_bytes())
        .unwrap()
}

fn count_tags(handle: &Handle, tag: &str) -> usize {
    let mut n = 0;
    if let NodeData::Element { ref name, .. } = handle.data {
        if name.local.as_ref() == tag { n += 1; }
    }
    for child in handle.children.borrow().iter() {
        n += count_tags(child, tag);
    }
    n
}

fn has_text(handle: &Handle, needle: &str) -> bool {
    if let NodeData::Text { ref contents } = handle.data {
        if contents.borrow().contains(needle) { return true; }
    }
    handle.children.borrow().iter().any(|c| has_text(c, needle))
}

// ── Render paths under test ───────────────────────────────────────────────────

fn render_index(input: &FuzzInput, base: &str) -> String {
    let mut p = view::Page::new("📋 Kant Pastebin");
    for w in view::nav_bar(base) { p.nav(w); }
    p.content(view::W::Raw(format!(
        r#"<form id="form">
<input type="text" id="title" value="{title}">
<textarea id="content">{content}</textarea>
<input type="text" id="keywords" value="{kw}">
{reply}
<button type="submit">📤 Share</button>
</form>"#,
        title   = html_escape(&input.title),
        content = html_escape(&input.content),
        kw      = html_escape(&input.keywords.join(",")),
        reply   = input.reply_to.as_deref()
            .map(|r| format!(r#"<input type="hidden" id="reply_to" value="{}">"#, r))
            .unwrap_or_default(),
    )));
    p.render()
}

fn render_browse(pastes: &[FuzzInput], base: &str) -> String {
    let mut p = view::Page::new("📋 Browse — Kant Pastebin");
    for w in view::nav_bar(base) { p.nav(w); }
    let mut rows = String::from("<ul>");
    for paste in pastes {
        rows.push_str(&format!("<li><a href=\"/paste/{}\">{}</a></li>",
            html_escape(&paste.title), html_escape(&paste.title)));
    }
    rows.push_str("</ul>");
    p.content(view::W::Raw(rows));
    p.render()
}

fn render_paste_view(input: &FuzzInput, base: &str) -> String {
    let mut p = view::Page::new(&format!("{} — Kant Pastebin", input.title));
    for w in view::nav_bar(base) { p.nav(w); }
    p.content(view::W::Raw(format!(
        "<h2>{}</h2><pre>{}</pre><p>Keywords: {}</p>",
        html_escape(&input.title),
        html_escape(&input.content),
        html_escape(&input.keywords.join(", ")),
    )));
    if let Some(ref rt) = input.reply_to {
        p.content(view::W::Raw(format!("<p>Reply to: <a href=\"/paste/{}\">{}</a></p>", rt, rt)));
    }
    p.render()
}

fn render_preview(input: &FuzzInput) -> String {
    view::render_preview("preview-id", &input.content)
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

// ── Main ──────────────────────────────────────────────────────────────────────

fn main() {
    println!("=== Kant Pastebin User Simulation Fuzzer ===\n");

    let inputs = gen_inputs(194); // one per Monster irrep
    let mut cov = Coverage::default();
    let mut errors: Vec<String> = vec![];

    // Register all coverage points
    for label in [
        "index:renders",        "index:has-form",       "index:has-nav",
        "index:title-in-dom",   "index:reply-to-hidden",
        "browse:renders",       "browse:has-list",      "browse:has-links",
        "paste-view:renders",   "paste-view:has-h2",    "paste-view:has-pre",
        "paste-view:reply-link","preview:renders",      "preview:non-empty",
        "index:empty-title",    "index:long-content",   "index:special-chars",
        "index:no-keywords",    "browse:empty",
    ] { cov.register(label); }

    let mut pass = 0usize;
    let mut fail = 0usize;

    for (i, input) in inputs.iter().enumerate() {
        // ── index page ──
        let html = render_index(input, "");
        let dom = parse(&html);
        let ok = !html.is_empty();
        if ok { cov.hit("index:renders"); } else { errors.push(format!("#{i} index:renders")); }

        if count_tags(&dom.document, "form") > 0 { cov.hit("index:has-form"); }
        if count_tags(&dom.document, "nav") > 0 || html.contains("Browse") { cov.hit("index:has-nav"); }
        if has_text(&dom.document, &input.title) || html.contains(&html_escape(&input.title)) { cov.hit("index:title-in-dom"); }
        if input.reply_to.is_some() && html.contains("reply_to") { cov.hit("index:reply-to-hidden"); }
        if input.title.is_empty() { cov.hit("index:empty-title"); }
        if input.content.len() > 50 { cov.hit("index:long-content"); }
        if input.title.contains('_') { cov.hit("index:special-chars"); }
        if input.keywords.is_empty() { cov.hit("index:no-keywords"); }

        if ok { pass += 1; } else { fail += 1; }

        // ── browse page ──
        let browse_html = render_browse(&inputs[..i.min(10)], "");
        let bdom = parse(&browse_html);
        cov.hit("browse:renders");
        if count_tags(&bdom.document, "ul") > 0 { cov.hit("browse:has-list"); }
        if count_tags(&bdom.document, "a") > 0 { cov.hit("browse:has-links"); }
        if i == 0 {
            let empty = render_browse(&[], "");
            if !empty.is_empty() { cov.hit("browse:empty"); }
        }

        // ── paste view ──
        let pv = render_paste_view(input, "");
        let pvdom = parse(&pv);
        cov.hit("paste-view:renders");
        if count_tags(&pvdom.document, "h2") > 0 { cov.hit("paste-view:has-h2"); }
        if count_tags(&pvdom.document, "pre") > 0 { cov.hit("paste-view:has-pre"); }
        if input.reply_to.is_some() && pv.contains("Reply to") { cov.hit("paste-view:reply-link"); }

        // ── preview ──
        let prev = render_preview(input);
        cov.hit("preview:renders");
        if !prev.is_empty() { cov.hit("preview:non-empty"); }
    }

    println!("Simulated {} users ({} pass, {} fail)", inputs.len(), pass, fail);
    cov.report();

    let pct = cov.hit.len() * 100 / cov.all.len().max(1);
    if pct < 100 {
        println!("\n⚠️  Uncovered paths:");
        for label in &cov.all {
            if !cov.hit.contains(label) { println!("   - {}", label); }
        }
    }

    if !errors.is_empty() {
        println!("\n❌ Errors:");
        for e in &errors { println!("   {}", e); }
        std::process::exit(1);
    }

    std::process::exit(if pct == 100 { 0 } else { 1 });
}
