use html5ever::parse_document;
use html5ever::tendril::TendrilSink;
use markup5ever_rcdom::{RcDom, Handle, NodeData};
use std::env;
use std::fs;

fn walk_dom(handle: &Handle, depth: usize) {
    let node = handle;
    match node.data {
        NodeData::Document => println!("Document → j-invariant (origin)"),
        NodeData::Element { ref name, .. } => {
            let coords = erdfa_dasl::orbifold_coords_full(depth);
            println!("{}Element <{}> → coords {:?}", 
                "  ".repeat(depth), name.local, &coords[..3]);
        }
        NodeData::Text { ref contents } => {
            let text = contents.borrow();
            if !text.trim().is_empty() {
                let coords = erdfa_dasl::orbifold_coords_full(text.len());
                println!("{}Text({} bytes) → coords {:?}", 
                    "  ".repeat(depth), text.len(), &coords[..3]);
            }
        }
        _ => {}
    }

    for child in node.children.borrow().iter() {
        walk_dom(child, depth + 1);
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: html_parser <file.html>");
        std::process::exit(1);
    }

    let html = fs::read_to_string(&args[1]).expect("read file");
    let dom = parse_document(RcDom::default(), Default::default())
        .from_utf8()
        .read_from(&mut html.as_bytes())
        .unwrap();

    walk_dom(&dom.document, 0);
}
