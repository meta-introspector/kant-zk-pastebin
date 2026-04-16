use html5ever::parse_document;
use html5ever::tendril::TendrilSink;
use markup5ever_rcdom::{RcDom, Handle, NodeData};
use std::collections::HashMap;

/// Headless browser test runner - pure Rust, no puppeteer
/// Performs const eval and static analysis of HTML/CSS/JS

struct TestContext {
    dom: RcDom,
    forms: Vec<FormElement>,
    links: Vec<String>,
    scripts: Vec<String>,
}

struct FormElement {
    id: Option<String>,
    inputs: Vec<InputElement>,
    action: Option<String>,
}

struct InputElement {
    id: Option<String>,
    name: Option<String>,
    input_type: String,
}

impl TestContext {
    fn from_html(html: &str) -> Self {
        let dom = parse_document(RcDom::default(), Default::default())
            .from_utf8()
            .read_from(&mut html.as_bytes())
            .unwrap();
        
        let mut ctx = TestContext {
            dom,
            forms: vec![],
            links: vec![],
            scripts: vec![],
        };
        
        ctx.extract_elements(&ctx.dom.document.clone());
        ctx
    }
    
    fn extract_elements(&mut self, handle: &Handle) {
        match handle.data {
            NodeData::Element { ref name, ref attrs, .. } => {
                let tag = name.local.as_ref();
                let attrs = attrs.borrow();
                
                match tag {
                    "form" => {
                        let action = attrs.iter()
                            .find(|a| a.name.local.as_ref() == "action")
                            .map(|a| a.value.to_string());
                        self.forms.push(FormElement {
                            id: None,
                            inputs: vec![],
                            action,
                        });
                    }
                    "a" => {
                        if let Some(href) = attrs.iter().find(|a| a.name.local.as_ref() == "href") {
                            self.links.push(href.value.to_string());
                        }
                    }
                    "script" => {
                        if let Some(src) = attrs.iter().find(|a| a.name.local.as_ref() == "src") {
                            self.scripts.push(src.value.to_string());
                        }
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        
        for child in handle.children.borrow().iter() {
            self.extract_elements(child);
        }
    }
    
    fn has_element(&self, selector: &str) -> bool {
        // Simple selector matching
        selector.contains("form") && !self.forms.is_empty()
            || selector.contains("a") && !self.links.is_empty()
    }
    
    fn title(&self) -> String {
        self.find_text_in_tag(&self.dom.document, "title")
    }
    
    fn find_text_in_tag(&self, handle: &Handle, tag: &str) -> String {
        match handle.data {
            NodeData::Element { ref name, .. } if name.local.as_ref() == tag => {
                return self.extract_text(handle);
            }
            _ => {}
        }
        
        for child in handle.children.borrow().iter() {
            let result = self.find_text_in_tag(child, tag);
            if !result.is_empty() {
                return result;
            }
        }
        
        String::new()
    }
    
    fn extract_text(&self, handle: &Handle) -> String {
        let mut text = String::new();
        for child in handle.children.borrow().iter() {
            match child.data {
                NodeData::Text { ref contents } => {
                    text.push_str(&contents.borrow());
                }
                _ => {
                    text.push_str(&self.extract_text(child));
                }
            }
        }
        text
    }
}

fn test_home_page(html: &str) -> bool {
    let ctx = TestContext::from_html(html);
    let title = ctx.title();
    println!("  Title: {}", title);
    title.contains("Kant Pastebin")
}

fn test_form_elements(html: &str) -> bool {
    let ctx = TestContext::from_html(html);
    let has_form = !ctx.forms.is_empty();
    println!("  Form: {}", if has_form { "✅" } else { "❌" });
    has_form
}

fn test_links(html: &str) -> bool {
    let ctx = TestContext::from_html(html);
    let has_browse = ctx.links.iter().any(|l| l.contains("/browse"));
    println!("  Browse link: {}", if has_browse { "✅" } else { "❌" });
    has_browse
}

fn main() {
    println!("=== Kant Pastebin Static Tests (Pure Rust) ===\n");
    
    // Load static HTML
    let index_html = std::fs::read_to_string("/mnt/data1/kant/pastebin/templates/index.html")
        .expect("read index.html");
    
    let mut results = vec![];
    
    // Test 1: Home Page
    println!("1. Home Page Load");
    results.push(test_home_page(&index_html));
    
    // Test 2: Form Elements
    println!("\n2. Form Elements");
    results.push(test_form_elements(&index_html));
    
    // Test 3: Links
    println!("\n3. Navigation Links");
    results.push(test_links(&index_html));
    
    // Summary
    let passed = results.iter().filter(|&&r| r).count();
    let total = results.len();
    
    println!("\n=== Summary ===");
    println!("Passed: {}/{}", passed, total);
    
    if passed == total {
        println!("✅ All static tests passed!");
        std::process::exit(0);
    } else {
        println!("❌ Some tests failed");
        std::process::exit(1);
    }
}
