use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use hex;
use chrono;

// Escaped RDFa utilities (from escaped-rdfa crate)
pub fn escape_html(input: &str) -> String {
    input
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

pub fn unescape_html(input: &str) -> String {
    input
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&amp;", "&")
}

#[macro_export]
macro_rules! erdfa_ns {
    () => {
        "https://escaped-rdfa.github.io/namespace/docs/1.0.html#"
    };
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Paste {
    pub id: String,
    pub title: String,
    pub content: String,
    pub witness: String,
    pub timestamp: String,
}

impl Paste {
    pub fn new(title: String, content: String) -> Self {
        let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S").to_string();
        let id = format!("paste_{}", timestamp);
        
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let witness = hex::encode(hasher.finalize());
        
        Self { id, title, content, witness, timestamp }
    }
    
    pub fn to_html(&self) -> String {
        format!(r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{} - Kant Pastebin</title>
<style>
body{{font-family:monospace;max-width:800px;margin:20px auto;padding:20px;background:#0a0a0a;color:#0f0}}
h1{{color:#0ff}}
.meta{{color:#888;margin:10px 0}}
pre{{background:#1a1a1a;padding:15px;border:1px solid #0f0;overflow-x:auto}}
.exports{{margin:20px 0}}
button{{background:#0f0;color:#000;border:none;padding:10px 20px;margin:5px;cursor:pointer}}
</style>
</head>
<body>
<h1>{}</h1>
<div class="meta">
  <div>ID: {}</div>
  <div>Witness: {}</div>
  <div>Created: {}</div>
</div>
<pre>{}</pre>
<div class="exports">
  <h2>Export Options</h2>
  <button onclick="location.href='/paste/{}/qr'">📱 QR Code</button>
  <button onclick="location.href='/paste/{}/rdfa'">🔗 Escaped RDFa</button>
  <button onclick="navigator.clipboard.writeText(location.href)">📋 Copy URL</button>
</div>
</body>
</html>"#,
            self.title, self.title, self.id, self.witness, self.timestamp, 
            escape_html(&self.content), self.id, self.id)
    }
    
    pub fn to_rdfa(&self) -> String {
        let escaped_title = escape_html(&self.title);
        let escaped_content = escape_html(&self.content);
        
        format!(
r#"&lt;div xmlns=&quot;http://www.w3.org/1999/xhtml&quot;
     prefix=&quot;eRDFa: {}
             schema: http://schema.org/
             dc: http://purl.org/dc/terms/&quot;&gt;
  &lt;div rel=&quot;eRDFa:embedded&quot;&gt;
    &lt;div about=&quot;#{}&quot; typeof=&quot;schema:CreativeWork&quot;&gt;
      &lt;span property=&quot;schema:name&quot;&gt;{}&lt;/span&gt;
      &lt;span property=&quot;dc:created&quot;&gt;{}&lt;/span&gt;
      &lt;span property=&quot;schema:sha256&quot;&gt;{}&lt;/span&gt;
      &lt;pre property=&quot;schema:text&quot;&gt;{}&lt;/pre&gt;
    &lt;/div&gt;
  &lt;/div&gt;
&lt;/div&gt;"#,
            erdfa_ns!(),
            self.id,
            escaped_title,
            self.timestamp,
            self.witness,
            escaped_content
        )
    }
    
    pub fn to_qr_url(&self) -> String {
        let base = std::env::var("BASE_URL").unwrap_or_else(|_| "http://localhost:8090".to_string());
        let path = std::env::var("BASE_PATH").unwrap_or_default();
        format!("{}{}/paste/{}", base, path, self.id)
    }
    
    pub fn to_monster_coords(&self) -> [u64; 6] {
        let mut hasher = Sha256::new();
        hasher.update(self.content.as_bytes());
        let hash = hasher.finalize();
        
        [
            u64::from_be_bytes(hash[0..8].try_into().unwrap()) % 71,
            u64::from_be_bytes(hash[8..16].try_into().unwrap()) % 59,
            u64::from_be_bytes(hash[16..24].try_into().unwrap()) % 47,
            u64::from_be_bytes(hash[24..32].try_into().unwrap()) % 71,
            u64::from_be_bytes(hash[0..8].try_into().unwrap()) % 59,
            u64::from_be_bytes(hash[8..16].try_into().unwrap()) % 47,
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_escape_html() {
        assert_eq!(escape_html("<div>"), "&lt;div&gt;");
        assert_eq!(escape_html("\"test\""), "&quot;test&quot;");
    }

    #[test]
    fn test_unescape_html() {
        assert_eq!(unescape_html("&lt;div&gt;"), "<div>");
        assert_eq!(unescape_html("&quot;test&quot;"), "\"test\"");
    }

    #[test]
    fn test_paste_creation() {
        let paste = Paste::new("Test".to_string(), "Hello World".to_string());
        assert!(paste.id.starts_with("paste_"));
        assert_eq!(paste.witness.len(), 64); // SHA256 hex
    }

    #[test]
    fn test_html_generation() {
        let paste = Paste::new("Test".to_string(), "Content".to_string());
        let html = paste.to_html();
        assert!(html.contains("<!DOCTYPE html>"));
        assert!(html.contains("Test"));
    }

    #[test]
    fn test_rdfa_generation() {
        let paste = Paste::new("Test".to_string(), "Content".to_string());
        let rdfa = paste.to_rdfa();
        assert!(rdfa.contains("&lt;div"));
        assert!(rdfa.contains("schema:CreativeWork"));
        assert!(rdfa.contains("eRDFa:embedded"));
    }

    #[test]
    fn test_monster_coords() {
        let paste = Paste::new("Test".to_string(), "Content".to_string());
        let coords = paste.to_monster_coords();
        assert!(coords[0] < 71);
        assert!(coords[1] < 59);
        assert!(coords[2] < 47);
    }
}
