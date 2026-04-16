use oxc_allocator::Allocator;
use oxc_parser::Parser;
use oxc_span::SourceType;
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: js_parser <file.js>");
        std::process::exit(1);
    }

    let source = fs::read_to_string(&args[1]).expect("read file");
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(&args[1]).unwrap_or_default();
    let ret = Parser::new(&allocator, &source, source_type).parse();

    if ret.errors.is_empty() {
        println!("✓ {} parsed successfully", args[1]);
        println!("  {} statements", ret.program.body.len());
    } else {
        eprintln!("✗ {} parse errors:", args[1]);
        for error in &ret.errors {
            eprintln!("  {}", error);
        }
        std::process::exit(1);
    }
}
