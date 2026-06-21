// View - HTML rendering for kant-pastebin
use crate::model::{PasteIndex, ThreadPost};

/// Render paste view page
pub fn render_paste(paste: &PasteIndex, content: &str, base_path: &str) -> String {
    let reply_info = if let Some(ref reply_id) = paste.reply_to {
        format!(
            r#"
<div style="background:#111;border-left:3px solid #00f;padding:10px;margin:10px 0;color:#00f">
    ↩️ In reply to: <a href="{bp}/paste/{rid}" style="color:#0ff">{rid}</a>
</div>"#,
            rid = reply_id,
            bp = base_path
        )
    } else {
        String::new()
    };

    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>{title} - kant-pastebin</title>
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
    <div><a href="{bp}/">🏠 Home</a> <a href="{bp}/browse">← Browse</a> <a href="{bp}/raw/{pid}">📄 Raw</a></div>
    <h1>{title}</h1>
    <p>ID: {pid} | {ts}</p>
    {reply}
    <a class="reply-btn" href="{bp}/?reply_to={pid}">💬 Reply</a>
    <a class="reply-btn" href="{bp}/paste/{pid}/split">✂️ Split</a>
    <button class="reply-btn" onclick="copyRaw()">📋 Copy HTML</button>
    <pre id="src">{content}</pre>
    <script>
    function copyRaw(){{
      var t=document.getElementById('src').textContent;
      navigator.clipboard.writeText(t).then(function(){{
        event.target.textContent='✅ Copied!';
        setTimeout(function(){{event.target.textContent='📋 Copy HTML'}},1500);
      }});
    }}
    </script>
</body>
</html>"#,
        title = paste.title,
        bp = base_path,
        pid = paste.id,
        ts = paste.timestamp,
        reply = reply_info,
        content = html_escape(content)
    )
}

/// Render paste split page
pub fn render_split_paste(paste: &PasteIndex, _content: &str, base_path: &str) -> String {
    let title = html_escape(&paste.title);
    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Split {title} - kant-pastebin</title>
    <style>
        body {{ background: #000; color: #0f0; font-family: monospace; padding: 20px; }}
        a {{ color: #0ff; text-decoration: none; margin-right: 10px; }}
        button {{ background: #0f0; color: #000; border: none; padding: 8px 12px; cursor: pointer; margin: 5px; }}
        button:disabled {{ background: #333; color: #666; cursor: not-allowed; }}
        .nav {{ margin-bottom: 20px; }}
        select {{ background: #111; color: #0f0; border: 1px solid #0f0; padding: 6px; margin: 5px; }}
        .panel {{ background: #111; border: 1px solid #0f0; padding: 15px; margin: 15px 0; }}
        .status {{ color: #0f0; margin: 10px 0; white-space: pre-wrap; }}
        .preview {{ background: #0a0a0a; border-left: 3px solid #0ff; padding: 10px; white-space: pre-wrap; word-wrap: break-word; max-height: 360px; overflow: auto; }}
    </style>
</head>
<body>
    <div class="nav"><a href="{bp}/">🏠 Home</a> <a href="{bp}/browse">← Browse</a> <a href="{bp}/paste/{pid}">← Paste</a> <a href="{bp}/raw/{pid}">📄 Raw</a></div>
    <h1>✂️ Split paste: {title}</h1>
    <p>ID: {pid} | {ts}</p>
    <div class="panel">
      <div>
        <label>Chunk size: </label>
        <select id="chunkSize">
          <option value="131072">128 KB</option>
          <option value="262144">256 KB</option>
          <option value="524288">512 KB</option>
          <option value="1048576" selected>1 MB</option>
          <option value="2097152">2 MB</option>
          <option value="4194304">4 MB</option>
          <option value="8388608">8 MB</option>
        </select>
      </div>
      <div>
        <label>Boundary: </label>
        <select id="splitMode">
          <option value="line">Newline</option>
          <option value="word">Word boundary</option>
          <option value="exact" selected>Exact bytes</option>
        </select>
      </div>
      <button onclick="splitText(event)">✂️ Split</button>
      <button onclick="downloadAllChunks(event)">💾 Download ZIP</button>
      <button onclick="uploadAllChunks(event)">📤 Upload Chunks as Pastes</button>
    </div>
    <div id="status" class="status"></div>
    <div id="preview" class="panel preview" style="display:none"></div>
    <script>
    function formatSize(bytes) {{
      if (bytes >= 1048576) return (bytes / 1048576).toFixed(2) + ' MB';
      if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
      return bytes + ' B';
    }}
    function splitBody() {{
      return {{
        paste_id: '{pid}',
        chunk_size: Number(document.getElementById('chunkSize').value),
        overlap: 0,
        unit: 'byte',
        split_mode: document.getElementById('splitMode').value
      }};
    }}
    async function splitText(event) {{
      const btn = event.target;
      const status = document.getElementById('status');
      btn.disabled = true;
      btn.textContent = '⏳ Splitting server-side...';
      status.textContent = 'Splitting server-side; raw content stays out of the browser.';
      const res = await fetch('{bp}/api/split-paste', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify(Object.assign({{preview_chars: 500, preview_chunks: 3}}, splitBody()))
      }});
      const data = await res.json();
      if (data.error) {{ status.textContent = 'Error: ' + data.error; btn.disabled = false; btn.textContent = '✂️ Split'; return; }}
      status.textContent = 'Split complete: ' + data.chunks + ' chunks · ' + formatSize(data.total_size) + ' input · ' + formatSize(data.chunk_size) + ' chunks · ' + data.word_count + ' words · ' + data.estimated_tokens + ' estimated tokens';
      renderPreview(data.preview_chunks || []);
      btn.disabled = false;
      btn.textContent = '✂️ Split';
    }}
    function renderPreview(chunks) {{
      const box = document.getElementById('preview');
      box.style.display = 'block';
      if (!chunks.length) {{ box.textContent = 'No preview returned; use Download ZIP to get all chunk text files.'; return; }}
      box.innerHTML = chunks.map(c => '<h3>Chunk ' + (c.index + 1) + ' (' + c.byte_len + ' bytes)</h3><pre>' + escapeHtml(c.text || '') + '</pre>').join('');
    }}
    async function downloadAllChunks(event) {{
      const btn = event.target;
      const status = document.getElementById('status');
      btn.disabled = true;
      btn.textContent = '⏳ Preparing ZIP...';
      status.textContent = 'Preparing ZIP server-side.';
      const res = await fetch('{bp}/api/split-download', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify(splitBody())
      }});
      if (!res.ok) {{ status.textContent = 'Error: ' + await res.text(); btn.disabled = false; btn.textContent = '💾 Download ZIP'; return; }}
      const blob = await res.blob();
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'split_chunks.zip';
      a.click();
      URL.revokeObjectURL(a.href);
      status.textContent = 'ZIP download started.';
      btn.disabled = false;
      btn.textContent = '💾 Download ZIP';
    }}
    async function uploadAllChunks(event) {{
      const btn = event.target;
      const status = document.getElementById('status');
      btn.disabled = true;
      btn.textContent = '⏳ Uploading chunks...';
      status.textContent = 'Uploading chunks as pastes.';
      const res = await fetch('{bp}/api/split-upload', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify(Object.assign({{title: 'split_{pid}'}}, splitBody()))
      }});
      const data = await res.json();
      if (data.error) {{ status.textContent = 'Error: ' + data.error; btn.disabled = false; btn.textContent = '📤 Upload Chunks as Pastes'; return; }}
      status.textContent = 'Opening chunk index paste...';
      window.location = '{bp}/paste/' + data.index_id;
    }}
    function escapeHtml(s) {{ return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }}
    </script>
</body>
</html>"#,
        title = title,
        bp = base_path,
        pid = paste.id,
        ts = paste.timestamp
    )
}

/// Render thread roots page
pub fn render_threads_page(
    base_path: &str,
    page: usize,
    total_pages: usize,
    total: usize,
    roots: &[PasteIndex],
) -> String {
    let rows = roots
        .iter()
        .map(|entry| {
            let title = if entry.title.is_empty() || entry.title == "untitled" {
                entry.description.as_deref().unwrap_or("untitled")
            } else {
                &entry.title
            };
            format!(
                r#"<div class="thread-root"><a href="{bp}/thread/{id}">{title}</a><div class="meta">{ts} · {size} bytes</div><div class="meta">ID: {id}</div></div>"#,
                bp = base_path,
                id = html_escape(&entry.id),
                title = html_escape(title),
                ts = html_escape(&entry.timestamp),
                size = entry.size
            )
        })
        .collect::<Vec<_>>()
        .join("");

    let pager = render_thread_pager(base_path, "/threads", page, total_pages);

    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Threads - kant-pastebin</title>
<style>
body{{background:#000;color:#0f0;font-family:monospace;padding:20px}}
a{{color:#0ff;text-decoration:none;margin-right:10px}}
.nav{{background:#111;padding:10px;margin:10px 0;border:1px solid #0f0}}
.thread-root{{border-bottom:1px solid #333;padding:12px 0}}
.meta{{color:#888;font-size:12px}}
.pager{{margin:15px 0}}
</style>
</head>
<body>
<div class="nav"><a href="{bp}/">🏠 Home</a> <a href="{bp}/browse">📚 Browse</a> <a href="{bp}/threads">🧵 Threads</a></div>
<h1>🧵 Thread Roots</h1>
<p class="meta">{total} threads · page {page}/{total_pages}</p>
{pager}
<div id="threads">{rows}</div>
{pager}
</body>
</html>"#,
        bp = base_path,
        total = total,
        page = page,
        total_pages = total_pages,
        rows = rows,
        pager = pager
    )
}

/// Render paginated threaded view
pub fn render_thread_page(
    base_path: &str,
    thread_id: &str,
    page: usize,
    total_pages: usize,
    total: usize,
    posts: &[ThreadPost],
) -> String {
    let rows = posts
        .iter()
        .map(|post| {
            let indent = post.depth * 24;
            let reply = post
                .reply_to
                .as_ref()
                .map(|rid| format!(r#" <span class="meta">↩ {rid}</span>"#))
                .unwrap_or_default();
            let desc = post
                .description
                .as_ref()
                .map(|d| format!(r#"<div class="meta">{}</div>"#, html_escape(d)))
                .unwrap_or_default();
            let excerpt = if post.content_excerpt.is_empty() {
                String::new()
            } else {
                format!(
                    r#"<div class="excerpt">{}</div>"#,
                    html_escape(&post.content_excerpt)
                )
            };
            format!(
                r#"<article class="post" style="margin-left:{indent}px"><h2><a href="{bp}/paste/{id}">{title}</a></h2><div class="meta">{ts} · {size} bytes · ID: {id}{reply}</div>{desc}{excerpt}<button class="similar-btn" data-id="{id}">Find similar</button><div id="similar-{id}" class="similar-results"></div></article>"#,
                bp = base_path,
                id = html_escape(&post.id),
                title = html_escape(&post.title),
                ts = html_escape(&post.timestamp),
                size = post.size,
                reply = reply,
                desc = desc,
                excerpt = excerpt,
                indent = indent
            )
        })
        .collect::<Vec<_>>()
        .join("");

    let pager = render_thread_pager(
        base_path,
        &format!("/thread/{}", thread_id),
        page,
        total_pages,
    );

    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Thread - kant-pastebin</title>
<style>
body{{background:#000;color:#0f0;font-family:monospace;padding:20px}}
a{{color:#0ff;text-decoration:none;margin-right:10px}}
.nav{{background:#111;padding:10px;margin:10px 0;border:1px solid #0f0}}
.post{{border-left:3px solid #0f0;border-bottom:1px solid #333;padding:12px;margin:12px 0;background:#080808}}
.meta{{color:#888;font-size:12px}}
.excerpt{{color:#0a0;white-space:pre-wrap;word-wrap:break-word;margin:8px 0}}
.pager{{margin:15px 0}}
.similar-btn{{background:#0f0;color:#000;border:none;padding:5px 8px;cursor:pointer;margin-top:5px}}
.similar-results{{margin:8px 0}}
.similar-item{{border-left:2px solid #0ff;padding-left:8px;margin:6px 0}}
</style>
</head>
<body>
<div class="nav"><a href="{bp}/">🏠 Home</a> <a href="{bp}/browse">📚 Browse</a> <a href="{bp}/threads">🧵 Threads</a> <a href="{bp}/paste/{tid}">Paste</a> <a href="{bp}/raw/{tid}">Raw</a></div>
<h1>🧵 Thread</h1>
<p class="meta">ID: {tid} · {total} posts · page {page}/{total_pages}</p>
{pager}
<div id="thread">{rows}</div>
{pager}
<script>
function esc(s) {{ return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }}
document.querySelectorAll('.similar-btn').forEach(btn => {{
  btn.onclick = async () => {{
    const id = btn.dataset.id;
    const box = document.getElementById('similar-' + id);
    box.textContent = 'Searching...';
    const res = await fetch('{bp}/api/similar/' + encodeURIComponent(id) + '?limit=5');
    const data = await res.json();
    const results = data.results || [];
    if (!results.length) {{ box.textContent = 'No similar posts found.'; return; }}
    box.innerHTML = results.map(r => '<div class="similar-item"><a href="' + esc(r.url) + '">' + esc(r.title || r.id) + '</a> <span class="meta">score ' + Number(r.score || 0).toFixed(1) + ' · ' + esc(r.timestamp) + '</span><div class="excerpt">' + esc(r.excerpt || '') + '</div></div>').join('');
  }};
}});
</script>
</body>
</html>"#,
        bp = base_path,
        tid = html_escape(thread_id),
        total = total,
        page = page,
        total_pages = total_pages,
        rows = rows,
        pager = pager
    )
}

fn render_thread_pager(base_path: &str, path: &str, page: usize, total_pages: usize) -> String {
    let mut parts = Vec::new();
    if page > 1 {
        parts.push(format!(
            r#"<a href="{bp}{path}?page={}">← Prev</a>"#,
            page - 1,
            bp = base_path
        ));
    }
    parts.push(format!(
        r#"<span class="meta">Page {page}/{total_pages}</span>"#
    ));
    if page < total_pages {
        parts.push(format!(
            r#"<a href="{bp}{path}?page={}">Next →</a>"#,
            page + 1,
            bp = base_path
        ));
    }
    parts.join(" ")
}

/// Render search page
pub fn render_search(base_path: &str) -> String {
    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Search - kant-pastebin</title>
<style>
body {{ background:#000;color:#0f0;font-family:monospace;padding:20px; }}
a {{ color:#0ff;text-decoration:none;margin-right:10px; }}
input, select, button {{ background:#111;color:#0f0;border:1px solid #0f0;padding:8px;margin:5px; }}
button {{ background:#0f0;color:#000;cursor:pointer; }}
button:disabled {{ background:#333;color:#666;cursor:not-allowed; }}
.result {{ border-bottom:1px solid #333;padding:10px 0; }}
.excerpt {{ color:#8f8;color:#0a0;white-space:pre-wrap; }}
.meta {{ color:#888;font-size:12px; }}
.selected {{ background:#0f0;color:#000; }}
</style>
</head>
<body>
<div><a href="{}/">🏠 Home</a> <a href="{}/browse">📚 Browse</a> <a href="{}/api/search">🔍 API</a></div>
<h1>🔍 Search Pastes</h1>
<form id="searchForm">
  <input id="q" placeholder="Search query" style="width:500px">
  <select id="mode"><option value="phrase">Phrase</option><option value="all">All terms</option><option value="any">Any term</option></select>
  <select id="scope"><option value="all">All</option><option value="metadata">Metadata only</option><option value="content">Content only</option></select>
  <button type="submit">Search</button>
</form>
<div id="status"></div>
<div id="toolbar" style="display:none;margin-top:10px">
  <button id="selectVisible">Select Visible</button>
  <button id="clearSelected">Clear</button>
  <button id="bundleSelected">Bundle Selected as Paste</button>
  <button id="chunkSelected">Chunk Selected as Deduped Pastes</button>
</div>
<div id="results"></div>
<script>
let selected = new Set();
function esc(s) {{ return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }}
async function doSearch() {{
  const q = document.getElementById('q').value.trim();
  if (!q) return;
  const mode = document.getElementById('mode').value;
  const scope = document.getElementById('scope').value;
  document.getElementById('status').textContent = 'Searching...';
  const res = await fetch('{}/api/search?q=' + encodeURIComponent(q) + '&mode=' + mode + '&scope=' + scope + '&limit=100');
  const data = await res.json();
  document.getElementById('status').textContent = data.total + ' results';
  document.getElementById('toolbar').style.display = 'block';
  const out = document.getElementById('results');
  out.innerHTML = '';
  (data.results || []).forEach((r, i) => {{
    const div = document.createElement('div');
    div.className = 'result';
    div.innerHTML = '<input type="checkbox" data-id="' + esc(r.id) + '" data-source="' + esc(r.source || '') + '"> ' +
      '<a href="' + esc(r.url) + '">' + esc(r.title || r.id) + '</a> ' +
      '<span class="meta">[' + esc(r.match_type) + '] ' + esc(r.timestamp) + ' ' + esc(r.size) + ' bytes</span><br>' +
      '<div class="excerpt">' + esc(r.excerpt) + '</div>';
    const cb = div.querySelector('input');
    cb.onchange = () => {{ if (cb.checked) selected.add(cb.dataset.id); else selected.delete(cb.dataset.id); }};
    out.appendChild(div);
  }});
}}
document.getElementById('searchForm').onsubmit = e => {{ e.preventDefault(); doSearch(); }};
document.getElementById('selectVisible').onclick = () => {{
  document.querySelectorAll('#results input[type=checkbox]').forEach(cb => {{ cb.checked = true; selected.add(cb.dataset.id); }});
}};
document.getElementById('clearSelected').onclick = () => {{ selected.clear(); document.querySelectorAll('#results input[type=checkbox]').forEach(cb => cb.checked = false); }};
document.getElementById('bundleSelected').onclick = async () => {{
  const ids = Array.from(selected).filter(Boolean);
  if (!ids.length) return;
  const btn = document.getElementById('bundleSelected');
  btn.disabled = true;
  document.getElementById('status').textContent = 'Bundling...';
  btn.textContent = 'Bundling...';
  const res = await fetch('{}/api/search-results-bundle', {{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{results:Array.from(selected).map(id => ({{id}})), title:'search bundle: ' + document.getElementById('q').value}})}});
  const data = await res.json();
  if (data.url) {{
    document.getElementById('status').textContent = 'Opening bundle...';
    window.location = data.url.startsWith('/paste/') ? '{}/' + data.url.slice(1) : data.url;
  }}
  else {{ alert('Bundle error: ' + (data.error || 'unknown')); btn.disabled = false; btn.textContent = 'Bundle Selected as Paste'; }}
}};
document.getElementById('chunkSelected').onclick = async () => {{
  const ids = Array.from(selected).filter(Boolean);
  if (!ids.length) return;
  const btn = document.getElementById('chunkSelected');
  const chunkSize = Number(prompt('Chunk bytes per paste', '250000'));
  btn.disabled = true;
  document.getElementById('status').textContent = 'Deduplicating lines and chunking...';
  const res = await fetch('{}/api/search-results-chunks', {{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{results:ids.map(id => ({{id}})), title:'search chunks: ' + document.getElementById('q').value, chunk_size:Number.isFinite(chunkSize) && chunkSize > 0 ? chunkSize : 250000, overlap:0}})}});
  const data = await res.json();
  if (data.url) {{
    document.getElementById('status').textContent = 'Opening chunk manifest...';
    window.location = data.url.startsWith('/paste/') ? '{}/' + data.url.slice(1) : data.url;
  }}
  else {{ alert('Chunk error: ' + (data.error || 'unknown')); btn.disabled = false; btn.textContent = 'Chunk Selected as Deduped Pastes'; }}
}};
</script>
</body>
</html>"#,
        base_path, base_path, base_path, base_path, base_path, base_path, base_path, base_path
    )
}

/// Render preview page with code execution
pub fn render_preview(id: &str, content: &str) -> String {
    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Preview: {id}</title>
    <style>
        body {{ background: #000; color: #0f0; font-family: monospace; padding: 20px; }}
        pre {{ background: #111; padding: 20px; border: 1px solid #0f0; }}
    </style>
</head>
<body>
    <h1>Preview: {id}</h1>
    <pre>{content}</pre>
</body>
</html>"#,
        id = id,
        content = html_escape(content)
    )
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
