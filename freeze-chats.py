#!/usr/bin/env python3
"""freeze-chats: snapshot kiro-cli chat JSONs into a static GitHub Pages site."""
import json, html, sys, os, re, hashlib
from pathlib import Path
from datetime import datetime

def extract_turns(history):
    """Extract human-readable turns from chat history."""
    turns = []
    for h in history:
        u = h.get("user", {})
        a = h.get("assistant", {})
        # user content
        uc = u.get("content", "")
        if isinstance(uc, dict):
            if "Prompt" in uc: uc = uc["Prompt"].get("prompt", "")
            elif "ToolUseResults" in uc: uc = None
            else: uc = str(uc)
        if uc:
            turns.append(("user", str(uc)[:50000]))
        # assistant content
        if isinstance(a, dict):
            txt = a.get("content", "") or a.get("message", "") or a.get("Text", "")
            if not txt and "ToolUse" in a:
                tu = a["ToolUse"]
                txt = tu.get("content", "") if isinstance(tu, dict) else ""
            if txt:
                turns.append(("assistant", str(txt)[:50000]))
    return turns

def render_chat(data, filename):
    """Render a single chat to HTML."""
    cid = data.get("conversation_id", "unknown")
    history = data.get("history", [])
    transcript = data.get("transcript", [])
    summary = data.get("latest_summary", "")
    if isinstance(summary, list):
        summary = summary[0] if summary else ""
    turns = extract_turns(history)
    # prefer transcript if turns are mostly tool calls
    if not turns and transcript:
        turns = []
        for i, t in enumerate(transcript):
            role = "user" if i % 2 == 0 else "assistant"
            turns.append((role, str(t)))
    title = filename.replace(".json", "").replace("-compacted", "")
    h = hashlib.sha256(json.dumps(data, default=str).encode()).hexdigest()[:12]
    body = []
    for role, text in turns:
        cls = "user" if role == "user" else "asst"
        escaped = html.escape(text[:10000])
        body.append(f'<div class="msg {cls}"><span class="role">{role}</span><pre>{escaped}</pre></div>')
    summary_html = f'<details><summary>Session Summary</summary><pre>{html.escape(str(summary)[:5000])}</pre></details>' if summary else ""
    return title, cid, h, f"""<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<link rel="stylesheet" href="style.css">
</head><body>
<nav><a href="index.html">← Index</a></nav>
<h1>{html.escape(title)}</h1>
<p class="meta">ID: <code>{cid}</code> | Hash: <code>{h}</code></p>
{summary_html}
<div class="chat">{''.join(body)}</div>
</body></html>"""

def main():
    if len(sys.argv) < 2:
        print("Usage: freeze-chats <chat-dir-or-files...> [--out docs/]")
        sys.exit(1)
    args = sys.argv[1:]
    out = Path("docs")
    if "--out" in args:
        i = args.index("--out")
        out = Path(args[i + 1])
        args = args[:i] + args[i+2:]
    # collect json files
    files = []
    for a in args:
        p = Path(a)
        if p.is_dir():
            files.extend(sorted(p.rglob("*.json")))
        elif p.is_file():
            files.append(p)
    if not files:
        print("No JSON files found"); sys.exit(1)
    out.mkdir(parents=True, exist_ok=True)
    index_entries = []
    for f in files:
        try:
            data = json.loads(f.read_text())
        except Exception as e:
            print(f"skip {f}: {e}"); continue
        title, cid, h, page_html = render_chat(data, f.name)
        slug = re.sub(r'[^a-z0-9_-]', '_', title.lower())[:80]
        out_file = out / f"{slug}.html"
        out_file.write_text(page_html)
        mtime = datetime.fromtimestamp(f.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        index_entries.append((mtime, title, slug, cid, h))
        print(f"  {slug}.html")
    # style
    (out / "style.css").write_text("""
body{font-family:monospace;max-width:900px;margin:0 auto;padding:20px;background:#0a0a0a;color:#0f0}
a{color:#0ff}nav{margin-bottom:20px}h1{font-size:1.2em}
.meta{color:#888;font-size:0.85em}
.chat{display:flex;flex-direction:column;gap:8px}
.msg{padding:8px 12px;border-radius:6px;max-width:90%;overflow:auto}
.msg pre{white-space:pre-wrap;word-break:break-word;margin:4px 0;font-size:0.9em}
.user{background:#001a00;border:1px solid #0f03;align-self:flex-end}
.asst{background:#0a0a15;border:1px solid #00f3;align-self:flex-start}
.role{font-size:0.75em;color:#888;text-transform:uppercase}
details{margin:12px 0;padding:8px;border:1px solid #333;border-radius:4px}
summary{cursor:pointer;color:#0ff}
table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:6px 10px;border-bottom:1px solid #222}
th{color:#0ff}
""")
    # index
    rows = []
    for mtime, title, slug, cid, h in sorted(index_entries, reverse=True):
        rows.append(f'<tr><td>{mtime}</td><td><a href="{slug}.html">{html.escape(title)}</a></td><td><code>{h}</code></td></tr>')
    (out / "index.html").write_text(f"""<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Frozen Chats</title><link rel="stylesheet" href="style.css">
</head><body>
<h1>Frozen Chats ({len(index_entries)} sessions)</h1>
<p>Generated {datetime.now().strftime("%Y-%m-%d %H:%M")}</p>
<table><tr><th>Date</th><th>Session</th><th>Hash</th></tr>
{''.join(rows)}
</table></body></html>""")
    # .nojekyll for github pages
    (out / ".nojekyll").touch()
    print(f"\n✅ {len(index_entries)} chats frozen to {out}/")

if __name__ == "__main__":
    main()
