// View - HTML rendering for kant-pastebin
use crate::model::PasteIndex;

/// Render paste view page
pub fn render_paste(paste: &PasteIndex, content: &str) -> String {
    let reply_info = if let Some(ref reply_id) = paste.reply_to {
        format!(r#"
<div style="background:#111;border-left:3px solid #00f;padding:10px;margin:10px 0;color:#00f">
    ↩️ In reply to: <a href="/paste/{}" style="color:#0ff">{}</a>
</div>"#, reply_id, reply_id)
    } else {
        String::new()
    };

    format!(r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>{} - kant-pastebin</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ background: #000; color: #0f0; font-family: monospace; padding: 20px; }}
        pre {{ background: #111; padding: 20px; border: 1px solid #0f0; overflow-x: auto; }}
        a {{ color: #0ff; text-decoration: none; margin-right: 10px; }}
        .reply-btn {{ background: #0f0; color: #000; border: none; padding: 5px 10px; cursor: pointer; margin: 5px; display: inline-block; }}
        .reply-btn:hover {{ background: #0ff; }}
    </style>
</head>
<body>
    <div><a href="/">🏠 Home</a> <a href="/browse">← Browse</a> <a href="/raw/{}">📄 Raw</a></div>
    <h1>{}</h1>
    <p>ID: {} | {}</p>
    {}
    <a class="reply-btn" href="/?reply_to={}">💬 Reply</a>
    <pre>{}</pre>
    <script src="/static/a11y.js"></script>
</body>
</html>"#, 
        paste.title, 
        paste.id,
        paste.title, 
        paste.id, 
        paste.timestamp,
        reply_info,
        paste.id,
        html_escape(content)
    )
}

/// Render preview page with code execution
pub fn render_preview(id: &str, content: &str) -> String {
    format!(r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Preview: {}</title>
    <style>
        body {{ background: #000; color: #0f0; font-family: monospace; padding: 20px; }}
        pre {{ background: #111; padding: 20px; border: 1px solid #0f0; }}
    </style>
</head>
<body>
    <h1>Preview: {}</h1>
    <pre>{}</pre>
</body>
</html>"#, id, id, html_escape(content))
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
