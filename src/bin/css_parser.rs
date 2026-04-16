use cssparser::{Parser, ParserInput, Token};
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: css_parser <file.css>");
        std::process::exit(1);
    }

    let css = fs::read_to_string(&args[1]).expect("read file");
    let mut input = ParserInput::new(&css);
    let mut parser = Parser::new(&mut input);

    let mut depth = 0;
    while let Ok(token) = parser.next() {
        match token {
            Token::Ident(ref name) => {
                let coords = erdfa_dasl::orbifold_coords_full(name.len());
                println!("{}Ident({}) → coords {:?}", "  ".repeat(depth), name, &coords[..3]);
            }
            Token::CurlyBracketBlock => {
                println!("{}{{ → depth {}", "  ".repeat(depth), depth);
                depth += 1;
            }
            Token::Function(ref name) => {
                let coords = erdfa_dasl::orbifold_coords_full(name.len());
                println!("{}Function({}) → coords {:?}", "  ".repeat(depth), name, &coords[..3]);
            }
            _ => {}
        }
    }
}
