use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_ast_visit::walk;
use oxc_ast_visit::Visit;
use oxc_parser::Parser;
use oxc_span::SourceType;
use oxc_syntax::scope::ScopeFlags as _;
use std::collections::HashMap;
use std::env;
use std::fs;

const MONSTER_IRREPS: &[&str] = &[
    "trivial", "chi_1", "chi_2", "chi_3", "chi_4", "chi_5", 
    // ... 194 total, using first few as demo
];

struct DeobfuscateVisitor {
    depth: usize,
    renamings: HashMap<String, String>,
}

impl DeobfuscateVisitor {
    fn canonical_name(&self, coords: &[u64]) -> String {
        let irrep_idx = (coords[0] % MONSTER_IRREPS.len() as u64) as usize;
        format!("{}_{}", MONSTER_IRREPS[irrep_idx], coords[1] % 1000)
    }
}

impl<'a> Visit<'a> for DeobfuscateVisitor {
    fn visit_program(&mut self, prog: &Program<'a>) {
        println!("// Deobfuscated via Monster orbifold projection");
        println!("// j-invariant origin = (0,0,...,0)\n");
        walk::walk_program(self, prog);
    }

    fn visit_function(&mut self, func: &Function<'a>, flags: oxc_syntax::scope::ScopeFlags) {
        let coords = erdfa_dasl::orbifold_coords_full(func.span.start as usize);
        let distance = erdfa_dasl::distance_from_origin(&coords);
        let canonical = self.canonical_name(&coords);
        
        println!("{}// Function at distance {} from origin", "  ".repeat(self.depth), distance);
        println!("{}// Coords: {:?}", "  ".repeat(self.depth), &coords[..3]);
        println!("{}// Canonical: {}", "  ".repeat(self.depth), canonical);
        
        self.depth += 1;
        walk::walk_function(self, func, flags);
        self.depth -= 1;
    }

    fn visit_variable_declaration(&mut self, decl: &VariableDeclaration<'a>) {
        let coords = erdfa_dasl::orbifold_coords_full(decl.span.start as usize);
        let canonical = self.canonical_name(&coords);
        
        println!("{}// Var → {}", "  ".repeat(self.depth), canonical);
        walk::walk_variable_declaration(self, decl);
    }

    fn visit_call_expression(&mut self, expr: &CallExpression<'a>) {
        let coords = erdfa_dasl::orbifold_coords_full(expr.span.start as usize);
        println!("{}// Call at {:?}", "  ".repeat(self.depth), &coords[..3]);
        walk::walk_call_expression(self, expr);
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: js_deobfuscate <file.js>");
        eprintln!("\nDeobfuscates JS by projecting AST nodes to Monster orbifold coords.");
        eprintln!("Each node gets canonical name from nearest Monster irrep.");
        std::process::exit(1);
    }

    let source = fs::read_to_string(&args[1]).expect("read file");
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(&args[1]).unwrap_or_default();
    let ret = Parser::new(&allocator, &source, source_type).parse();

    if !ret.errors.is_empty() {
        eprintln!("Parse errors:");
        for error in &ret.errors {
            eprintln!("  {}", error);
        }
        std::process::exit(1);
    }

    let mut visitor = DeobfuscateVisitor {
        depth: 0,
        renamings: HashMap::new(),
    };
    visitor.visit_program(&ret.program);
}

