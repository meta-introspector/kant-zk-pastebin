// View - Component-based HTML rendering for kant-pastebin
// Inspired by Tk: push named widgets into a layout, render once.

use std::collections::HashMap;

pub fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

// ── Widget ──────────────────────────────────────────────────

pub enum W {
    /// Raw HTML (no escaping)
    Raw(String),
    /// Text button: label, onclick JS
    Btn { label: String, onclick: String },
    /// Link button: label, href
    Link { label: String, href: String },
    /// Clickable command line (copies on click)
    Cmd { text: String },
    /// Hidden command (copies on click, shows short label)
    CmdHidden { label: String, text: String },
    /// Preformatted content
    Pre(String),
    /// Collapsible group
    Details { summary: String, children: Vec<W> },
    /// JS variable declaration
    JsVar { name: String, value: String },
    /// Inline script block
    Script(String),
}

// ── Page builder ────────────────────────────────────────────

pub struct Page {
    pub title: String,
    pub scripts: Vec<String>,
    nav: Vec<W>,
    actions: Vec<W>,
    commands: Vec<W>,
    body: Vec<W>,
    footer: Vec<W>,
    modals: Vec<W>,
    js_vars: Vec<(String, String)>,
    js_blocks: Vec<String>,
}

impl Page {
    pub fn new(title: &str) -> Self {
        Self {
            title: title.to_string(),
            scripts: vec![],
            nav: vec![],
            actions: vec![],
            commands: vec![],
            body: vec![],
            footer: vec![],
            modals: vec![],
            js_vars: vec![],
            js_blocks: vec![],
        }
    }

    pub fn script_src(&mut self, url: &str) -> &mut Self {
        self.scripts.push(url.to_string()); self
    }
    pub fn nav(&mut self, w: W) -> &mut Self { self.nav.push(w); self }
    pub fn action(&mut self, w: W) -> &mut Self { self.actions.push(w); self }
    pub fn cmd(&mut self, w: W) -> &mut Self { self.commands.push(w); self }
    pub fn content(&mut self, w: W) -> &mut Self { self.body.push(w); self }
    pub fn footer(&mut self, w: W) -> &mut Self { self.footer.push(w); self }
    pub fn modal(&mut self, w: W) -> &mut Self { self.modals.push(w); self }
    pub fn js_var(&mut self, name: &str, val: &str) -> &mut Self {
        self.js_vars.push((name.to_string(), val.to_string())); self
    }
    pub fn js(&mut self, code: &str) -> &mut Self {
        self.js_blocks.push(code.to_string()); self
    }

    pub fn render(&self) -> String {
        let mut h = String::with_capacity(8192);

        // Head
        h.push_str(&format!(
            r#"<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{}</title>
{}"#,
            html_escape(&self.title),
            CSS
        ));
        for s in &self.scripts {
            h.push_str(&format!("<script src=\"{}\"></script>\n", s));
        }
        h.push_str("</head><body>\n");

        // Nav
        if !self.nav.is_empty() {
            h.push_str("<div class=\"nav\">");
            for w in &self.nav { render_widget(w, &mut h); }
            h.push_str("</div>\n");
        }

        // Title
        h.push_str(&format!("<h1>{}</h1>\n", html_escape(&self.title)));

        // Actions
        if !self.actions.is_empty() {
            h.push_str("<div class=\"actions\">");
            for w in &self.actions { render_widget(w, &mut h); }
            h.push_str("</div>\n");
        }

        // Commands (collapsible)
        if !self.commands.is_empty() {
            h.push_str("<details class=\"cmd-group\"><summary>▶ Commands</summary>\n");
            for w in &self.commands { render_widget(w, &mut h); }
            h.push_str("</details>\n");
        }

        // Body
        for w in &self.body { render_widget(w, &mut h); }

        // Footer
        for w in &self.footer { render_widget(w, &mut h); }

        // Modals
        for w in &self.modals { render_widget(w, &mut h); }

        // JS
        h.push_str("<script>\n");
        for (k, v) in &self.js_vars {
            h.push_str(&format!("const {}='{}';\n", k, v.replace('\'', "\\'")));
        }
        for block in &self.js_blocks {
            h.push_str(block);
            h.push('\n');
        }
        h.push_str("</script>\n<script src=\"/static/a11y.js\"></script>\n</body></html>");
        h
    }
}

fn render_widget(w: &W, h: &mut String) {
    match w {
        W::Raw(s) => h.push_str(s),
        W::Btn { label, onclick } => {
            h.push_str(&format!(
                "<button class=\"reply-btn\" onclick=\"{}\">{}</button>",
                html_escape(onclick), label
            ));
        }
        W::Link { label, href } => {
            h.push_str(&format!(
                "<a class=\"reply-btn\" href=\"{}\">{}</a>",
                html_escape(href), label
            ));
        }
        W::Cmd { text } => {
            h.push_str(&format!(
                "<div class=\"cmd\" onclick=\"navigator.clipboard.writeText(this.dataset.v);this.style.borderColor='#0f0'\" data-v=\"{}\">$ {}</div>",
                html_escape(text), html_escape(text)
            ));
        }
        W::CmdHidden { label, text } => {
            h.push_str(&format!(
                "<div class=\"cmd\" onclick=\"navigator.clipboard.writeText(this.dataset.v);this.style.borderColor='#0f0'\" data-v=\"{}\">{}</div>",
                html_escape(text), label
            ));
        }
        W::Pre(text) => {
            h.push_str(&format!("<pre>{}</pre>", html_escape(text)));
        }
        W::Details { summary, children } => {
            h.push_str(&format!("<details><summary>{}</summary>", html_escape(summary)));
            for c in children { render_widget(c, h); }
            h.push_str("</details>");
        }
        W::JsVar { .. } | W::Script(_) => {} // handled in Page::render
    }
}

// ── CSS ─────────────────────────────────────────────────────

const CSS: &str = r#"<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:monospace;max-width:800px;margin:0 auto;padding:10px;background:#0a0a0a;color:#0f0;font-size:14px}
a{color:#0ff;text-decoration:none}
h1{font-size:1.2em;word-break:break-word;margin:8px 0}
.nav{background:#111;padding:8px;margin:8px 0;border:1px solid #0f0;display:flex;flex-wrap:wrap;gap:8px}
.actions{display:flex;flex-wrap:wrap;gap:4px;margin:8px 0}
.reply-btn{background:#0f0;color:#000;border:none;padding:8px 12px;cursor:pointer;font-size:13px;border-radius:3px}
.reply-btn:hover{background:#0ff}
.cmd-group{margin:8px 0}
.cmd-group summary{cursor:pointer;color:#ff0;padding:4px 0;font-size:13px}
.cmd{background:#111;padding:8px;margin:4px 0;border-left:3px solid #ff0;cursor:pointer;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cmd:hover{background:#222}
pre{background:#111;padding:12px;border:1px solid #0f0;overflow:auto;max-height:60vh;word-wrap:break-word;white-space:pre-wrap;font-size:13px}
.qr-modal{position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:#fff;padding:20px;border:3px solid #0f0;z-index:1000;display:none}
.qr-modal h3{color:#000}
@media(max-width:600px){body{padding:6px;font-size:13px}h1{font-size:1em}pre{padding:8px;font-size:12px;max-height:50vh}.reply-btn{padding:6px 8px;font-size:12px}.cmd{font-size:11px;padding:6px}}
</style>
"#;

// ── Shared JS functions ─────────────────────────────────────

pub const JS_QR: &str = r#"
function showQR(){renderQR(pasteUrl,'📎 URL QR')}
function showDataQR(){renderQR(dataUrl,'📦 Data QR (contains content)')}
function renderQR(data,label){
  var m=document.getElementById('qrModal');
  document.getElementById('qrLabel').textContent=label;
  m.style.display='block';
  var ecl=data.length>2000?'L':data.length>500?'M':'H';
  try{
    var qr=qrcode(0,ecl);qr.addData(data);qr.make();
    var c=document.getElementById('qrcode'),ctx=c.getContext('2d');
    var n=qr.getModuleCount(),sz=Math.max(256,n*4),cs=sz/n;
    c.width=sz;c.height=sz;
    ctx.fillStyle='#fff';ctx.fillRect(0,0,sz,sz);
    ctx.fillStyle='#000';
    for(var r=0;r<n;r++)for(var k=0;k<n;k++)if(qr.isDark(r,k))ctx.fillRect(k*cs,r*cs,cs,cs);
  }catch(e){document.getElementById('qrLabel').textContent='⚠️ Content too large for QR'}
}
"#;

pub const JS_SHARE: &str = r#"
function shareRDFa(){
  var u=pasteUrl+'#typeof=schema:CreativeWork&property=schema:name='+encodeURIComponent(title)+(ipfsCid?'&property=schema:identifier='+encodeURIComponent(ipfsCid):'');
  navigator.clipboard.writeText(u);alert('✅ RDFa URL copied')
}
function shareErdfa(){
  var u=dataUrl+'&erdfa=1&cid='+encodeURIComponent(ipfsCid);
  navigator.clipboard.writeText(u);alert('✅ eRDFa shard URL copied')
}
function decodeDataUrl(){
  var h=dataUrl.split('#z=')[1];if(!h){alert('No inline data');return}
  try{
    var b=Uint8Array.from(atob(h.replace(/-/g,'+').replace(/_/g,'/'))  ,function(c){return c.charCodeAt(0)});
    new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).text().then(function(t){
      var w=window.open('','_blank');
      w.document.write('<pre style="white-space:pre-wrap;font-family:monospace;padding:20px">'+t.replace(/</g,'&lt;')+'</pre>')
    })
  }catch(e){alert('Decode error: '+e)}
}
"#;

pub const JS_PREVIEW: &str = r#"
function showPreview(){
  var content=document.querySelector('pre').innerHTML;
  var modal=document.createElement('div');
  modal.style.cssText='position:fixed;top:0;left:0;width:100%;height:100%;background:#fff;z-index:2000;overflow:auto';
  var decoded=document.createElement('textarea');decoded.innerHTML=content;
  var ac=decoded.value;
  var sc=ac.includes('<html')||ac.includes('<!DOCTYPE')?ac:'<html><head><style>body{font-family:sans-serif;padding:20px;line-height:1.6}</style></head><body><pre style="white-space:pre-wrap;word-wrap:break-word">'+ac+'</pre></body></html>';
  modal.innerHTML='<button onclick="this.parentElement.remove()" style="position:fixed;top:10px;right:10px;z-index:3000;padding:10px 20px;background:#f00;color:#fff;border:none;cursor:pointer">✕ Close</button><iframe srcdoc="'+sc.replace(/"/g,'&quot;')+'" style="width:100%;height:100%;border:none"></iframe>';
  document.body.appendChild(modal)
}
"#;

pub const QR_MODAL: &str = r#"<div id="qrModal" class="qr-modal"><h3 id="qrLabel"></h3><canvas id="qrcode"></canvas><br><button onclick="document.getElementById('qrModal').style.display='none'">Close</button></div>"#;

pub const JS_COPY_HTML: &str = r#"
function copyHtml(){
  var el=document.querySelector('pre');
  var html=el.innerHTML;
  var blob=new Blob([html],{type:'text/html'});
  var item=new ClipboardItem({'text/html':blob,'text/plain':new Blob([el.textContent],{type:'text/plain'})});
  navigator.clipboard.write([item]).then(function(){
    event.target.textContent='✅ HTML copied'
  })
}
"#;

pub const JS_CROSSPOST: &str = r#"
function crossPost(){
  var url=prompt('Paste target URL (e.g. https://other-pastebin.example/paste)');
  if(!url)return;
  var content=document.querySelector('pre').textContent;
  fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({content:content,source:pasteUrl}),mode:'cors'})
    .then(function(r){return r.json()})
    .then(function(d){alert('✅ Cross-posted: '+(d.url||d.id||JSON.stringify(d)))})
    .catch(function(e){
      // Fallback: copy curl command
      var cmd='curl -X POST '+url+" -H 'Content-Type: application/json' -d "+JSON.stringify(JSON.stringify({content:content,source:pasteUrl}));
      navigator.clipboard.writeText(cmd);
      alert('⚠️ CORS blocked. Curl command copied to clipboard.')
    })
}
"#;

/// Render preview page
pub fn render_preview(id: &str, content: &str) -> String {
    let mut p = Page::new(&format!("Preview: {}", id));
    p.content(W::Pre(content.to_string()));
    p.render()
}
