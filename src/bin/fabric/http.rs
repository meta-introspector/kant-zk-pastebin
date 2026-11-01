//! A small HTTP/1.1 server and client.
//!
//! The fabric is a control plane: tens of requests per task, not thousands per
//! second. It therefore uses one thread per connection and blocks, which keeps
//! the dependency list at zero HTTP crates and makes the whole request path
//! readable in one sitting. Responses are `Connection: close` and always carry
//! an explicit `Content-Length`, so no pipelining state exists to get wrong.
//!
//! The client handles `Content-Length` and `Transfer-Encoding: chunked`, since
//! the IPFS gateway uses the latter for larger blocks.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

#[derive(Clone, Debug)]
pub struct Request {
    pub method: String,
    pub path: String,
    pub query: HashMap<String, String>,
    pub body: Vec<u8>,
}

impl Request {
    pub fn param(&self, k: &str) -> Option<&str> {
        self.query.get(k).map(|s| s.as_str())
    }

    pub fn json(&self) -> Result<serde_json::Value, String> {
        serde_json::from_slice(&self.body).map_err(|e| format!("body is not json: {e}"))
    }
}

pub struct Response {
    pub status: u16,
    pub body: Vec<u8>,
    pub content_type: String,
}

impl Response {
    pub fn json(status: u16, v: &serde_json::Value) -> Response {
        Response {
            status,
            body: serde_json::to_vec(v).unwrap_or_else(|_| b"{}".to_vec()),
            content_type: "application/json".into(),
        }
    }

    pub fn text(status: u16, s: impl Into<String>) -> Response {
        Response {
            status,
            body: s.into().into_bytes(),
            content_type: "text/plain; charset=utf-8".into(),
        }
    }

    pub fn bytes(status: u16, b: Vec<u8>) -> Response {
        Response { status, body: b, content_type: "application/octet-stream".into() }
    }

    pub fn error(status: u16, msg: impl Into<String>) -> Response {
        Response::json(status, &serde_json::json!({"ok": false, "error": msg.into()}))
    }
}

fn read_line<R: Read>(r: &mut R, max: usize) -> Result<String, String> {
    let mut out = Vec::new();
    let mut byte = [0u8; 1];
    loop {
        let n = r.read(&mut byte).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        if byte[0] == b'\n' {
            break;
        }
        if byte[0] != b'\r' {
            out.push(byte[0]);
        }
        if out.len() > max {
            return Err("header line too long".into());
        }
    }
    String::from_utf8(out).map_err(|e| e.to_string())
}

pub fn read_request<R: Read>(r: &mut R) -> Result<Request, String> {
    let line = read_line(r, 8192)?;
    if line.is_empty() {
        return Err("empty request".into());
    }
    let mut parts = line.split_whitespace();
    let method = parts.next().ok_or("no method")?.to_string();
    let target = parts.next().ok_or("no target")?.to_string();
    let (path, query) = match target.split_once('?') {
        Some((p, q)) => (p.to_string(), parse_query(q)),
        None => (target, HashMap::new()),
    };
    let mut headers: HashMap<String, String> = HashMap::new();
    loop {
        let h = read_line(r, 8192)?;
        if h.is_empty() {
            break;
        }
        if let Some((k, v)) = h.split_once(':') {
            headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
        }
    }
    let len: usize = headers
        .get("content-length")
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    if len > 8 * 1024 * 1024 {
        return Err("body too large".into());
    }
    let mut body = vec![0u8; len];
    if len > 0 {
        r.read_exact(&mut body).map_err(|e| format!("short body: {e}"))?;
    }
    Ok(Request { method, path, query, body })
}

fn parse_query(q: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for pair in q.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        map.insert(percent_decode(k), percent_decode(v));
    }
    map
}

fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'%' if i + 2 < b.len() => {
                let hex = std::str::from_utf8(&b[i + 1..i + 3]).unwrap_or("");
                match u8::from_str_radix(hex, 16) {
                    Ok(x) => {
                        out.push(x);
                        i += 3;
                    }
                    Err(_) => {
                        out.push(b'%');
                        i += 1;
                    }
                }
            }
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            c => {
                out.push(c);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).to_string()
}

fn write_response<W: Write>(w: &mut W, r: &Response) -> Result<(), String> {
    let head = format!(
        "HTTP/1.1 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
        r.status,
        status_text(r.status),
        r.content_type,
        r.body.len()
    );
    w.write_all(head.as_bytes()).map_err(|e| e.to_string())?;
    w.write_all(&r.body).map_err(|e| e.to_string())?;
    w.flush().map_err(|e| e.to_string())
}

fn status_text(s: u16) -> &'static str {
    match s {
        200 => "OK",
        201 => "Created",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        _ => "Unknown",
    }
}

pub type Handler = Arc<dyn Fn(Request) -> Response + Send + Sync>;

pub fn handle_stream<S: Read + Write>(mut s: S, handler: &Handler) {
    let req = match read_request(&mut s) {
        Ok(r) => r,
        Err(e) => {
            let _ = write_response(&mut s, &Response::error(400, e));
            return;
        }
    };
    let resp = handler(req);
    let _ = write_response(&mut s, &resp);
}

pub fn serve_tcp(listener: TcpListener, handler: Handler) -> std::io::Result<()> {
    for conn in listener.incoming() {
        match conn {
            Ok(s) => {
                let h = handler.clone();
                thread::spawn(move || {
                    s.set_read_timeout(Some(Duration::from_secs(30))).ok();
                    s.set_write_timeout(Some(Duration::from_secs(30))).ok();
                    handle_stream(s, &h);
                });
            }
            Err(e) => eprintln!("fabric: accept: {e}"),
        }
    }
    Ok(())
}

// ---------------------------------------------------------------- client

#[derive(Debug)]
pub struct Url {
    pub host: String,
    pub port: u16,
    pub path: String,
}

pub fn parse_url(url: &str) -> Result<Url, String> {
    let rest = url
        .strip_prefix("http://")
        .ok_or_else(|| format!("only http:// is supported: {url}"))?;
    let (authority, path) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, "/"),
    };
    let (host, port) = match authority.rsplit_once(':') {
        Some((h, p)) if p.chars().all(|c| c.is_ascii_digit()) && !p.is_empty() => {
            (h.to_string(), p.parse::<u16>().map_err(|e| e.to_string())?)
        }
        _ => (authority.to_string(), 80),
    };
    Ok(Url { host, port, path: path.to_string() })
}

pub struct HttpResult {
    pub status: u16,
    pub body: Vec<u8>,
}

impl HttpResult {
    pub fn json(&self) -> Result<serde_json::Value, String> {
        serde_json::from_slice(&self.body).map_err(|e| {
            format!(
                "not json (status {}): {}",
                self.status,
                String::from_utf8_lossy(&self.body[..self.body.len().min(200)])
            )
        })
    }
}

pub fn request(
    method: &str,
    url: &str,
    body: Option<(&str, Vec<u8>)>,
    timeout: Duration,
) -> Result<HttpResult, String> {
    let u = parse_url(url)?;
    let addr = format!("{}:{}", u.host, u.port);
    let mut s = TcpStream::connect_timeout(
        &std::net::ToSocketAddrs::to_socket_addrs(&addr)
            .map_err(|e| e.to_string())?
            .next()
            .ok_or_else(|| format!("no address for {addr}"))?,
        timeout,
    )
    .map_err(|e| format!("connect {addr}: {e}"))?;
    s.set_read_timeout(Some(timeout)).ok();
    s.set_write_timeout(Some(timeout)).ok();
    let (ctype, payload) = match body {
        Some((c, b)) => (c, b),
        None => ("application/octet-stream", Vec::new()),
    };
    let head = format!(
        "{method} {} HTTP/1.1\r\nHost: {}\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        u.path,
        u.host,
        payload.len()
    );
    s.write_all(head.as_bytes()).map_err(|e| e.to_string())?;
    s.write_all(&payload).map_err(|e| e.to_string())?;
    let mut raw = Vec::new();
    s.read_to_end(&mut raw).map_err(|e| e.to_string())?;
    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or("no header terminator")?;
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let mut rest = raw[split + 4..].to_vec();
    let status: u16 = head
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| format!("bad status line: {head}"))?;
    let chunked = head.to_ascii_lowercase().contains("transfer-encoding: chunked");
    if chunked {
        rest = dechunk(&rest)?;
    }
    Ok(HttpResult { status, body: rest })
}

fn dechunk(mut data: &[u8]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    loop {
        let idx = data
            .windows(2)
            .position(|w| w == b"\r\n")
            .ok_or("chunk header not terminated")?;
        let size_s = String::from_utf8_lossy(&data[..idx]).to_string();
        let size = usize::from_str_radix(size_s.split(';').next().unwrap_or("").trim(), 16)
            .map_err(|e| format!("bad chunk size {size_s:?}: {e}"))?;
        data = &data[idx + 2..];
        if size == 0 {
            return Ok(out);
        }
        if data.len() < size + 2 {
            return Err("truncated chunk".into());
        }
        out.extend_from_slice(&data[..size]);
        data = &data[size + 2..];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_request_with_query_and_body() {
        let raw = b"POST /tasks/abc/claim?lease=30 HTTP/1.1\r\nHost: x\r\nContent-Length: 7\r\n\r\n{\"a\":1}";
        let req = read_request(&mut &raw[..]).unwrap();
        assert_eq!(req.method, "POST");
        assert_eq!(req.path, "/tasks/abc/claim");
        assert_eq!(req.param("lease"), Some("30"));
        assert_eq!(req.body, b"{\"a\":1}");
    }

    #[test]
    fn decodes_percent_escapes() {
        assert_eq!(percent_decode("a%20b+c"), "a b c");
        assert_eq!(percent_decode("%zz"), "%zz");
    }

    #[test]
    fn parses_url_with_and_without_port() {
        let a = parse_url("http://127.0.0.1:8787/health").unwrap();
        assert_eq!((a.host.as_str(), a.port, a.path.as_str()), ("127.0.0.1", 8787, "/health"));
        let b = parse_url("http://example.org").unwrap();
        assert_eq!((b.host.as_str(), b.port, b.path.as_str()), ("example.org", 80, "/"));
    }

    #[test]
    fn dechunks_in_order() {
        let raw = b"4\r\nwiki\r\n5\r\npedia\r\n0\r\n\r\n";
        assert_eq!(dechunk(raw).unwrap(), b"wikipedia");
    }
}
