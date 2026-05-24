//! Decl Tile plugin — parse Rust source with `syn` and render an interactive AST tree.
//! POST /plugin/decl_tile?action=parse with Rust source code → interactive HTML tree.
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct DeclTilePlugin;

impl DeclTilePlugin {
    pub fn new() -> Self { Self }
}

impl Plugin for DeclTilePlugin {
    fn name(&self) -> &str { "decl_tile" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str {
        "Rust AST viewer — parse Rust source code and display an interactive syntax tree"
    }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("parse");
        let content = std::str::from_utf8(&input.content).unwrap_or("").to_string();

        match action {
            "parse" | "ast" => {
                if content.trim().is_empty() {
                    map.insert("error".to_string(),
                        "No Rust source provided. Send Rust code as POST body.".to_string());
                    return Ok(map);
                }
                match parse_rust_source(&content) {
                    Ok((tree_json, stats)) => {
                        let html = wrap_decl_html("ast-viewer", &tree_json, &stats);
                        map.insert("html".to_string(), html);
                        map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
                    }
                    Err(e) => {
                        map.insert("error".to_string(), format!("Parse error: {}", e));
                    }
                }
            }
            "raw" => {
                if content.trim().is_empty() {
                    map.insert("error".to_string(), "No Rust source provided.".to_string());
                    return Ok(map);
                }
                match parse_rust_source(&content) {
                    Ok((tree_json, stats)) => {
                        map.insert("json".to_string(), tree_json);
                        map.insert("stats".to_string(), serde_json::to_string(&stats).unwrap_or_default());
                        map.insert("content_type".to_string(), "application/json".to_string());
                    }
                    Err(e) => {
                        map.insert("error".to_string(), format!("Parse error: {}", e));
                    }
                }
            }
            "help" | _ => {
                map.insert("html".to_string(), r#"<h1>📐 Decl Tile — Rust AST Viewer</h1>
<p>Parse Rust source code and explore its abstract syntax tree interactively.</p>
<form id="dt-form">
  <label>Rust source code:</label><br>
  <textarea name="code" rows="16" cols="80" placeholder="fn main() { println!(&quot;hello&quot;); }"></textarea><br>
  <button onclick="submitDecl()">Parse AST</button>
</form>
<div id="dt-output"></div>
<script>
function submitDecl() {
  const data = document.querySelector('#dt-form textarea').value;
  fetch('/plugin/decl_tile/test', {
    method: 'POST',
    headers: {'Content-Type': 'text/plain'},
    body: data
  }).then(r => r.text()).then(html => {
    document.querySelector('#dt-output').innerHTML = html;
  });
}
</script>"#.to_string());
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            }
        }
        Ok(map)
    }
}

#[derive(serde::Serialize)]
struct AstNode {
    name: String,
    kind: String,
    span: String,
    details: HashMap<String, String>,
    children: Vec<AstNode>,
}

#[derive(serde::Serialize)]
struct AstStats {
    node_count: usize,
    depth: usize,
    item_count: usize,
    fn_count: usize,
    struct_count: usize,
    enum_count: usize,
    trait_count: usize,
    impl_count: usize,
    error_count: usize,
}

fn parse_rust_source(source: &str) -> Result<(String, AstStats), String> {
    let syntax = syn::parse_file(source).map_err(|e| format!("{}", e))?;

    let mut root = AstNode {
        name: source_file_name(&syntax),
        kind: "SourceFile".to_string(),
        span: format!("1:1-{}:{}", line_count(source), source.lines().last().map(|l| l.len()).unwrap_or(0)),
        details: {
            let mut d = HashMap::new();
            d.insert("shebang".to_string(), syntax.shebang.as_deref().unwrap_or("none").to_string());
            d
        },
        children: Vec::new(),
    };

    let mut stats = AstStats {
        node_count: 0,
        depth: 0,
        item_count: 0,
        fn_count: 0,
        struct_count: 0,
        enum_count: 0,
        trait_count: 0,
        impl_count: 0,
        error_count: 0,
    };

    // Walk top-level items
    for item in &syntax.items {
        let (node, depth) = convert_item(item, 1);
        stats.depth = stats.depth.max(depth);
        count_item(item, &mut stats);
        stats.node_count += count_nodes(&node);
        root.children.push(node);
    }

    // Also walk attributes on the file level
    for attr in &syntax.attrs {
        let mut details = HashMap::new();
        details.insert("path".to_string(), attr.path().to_token_stream().to_string());
        details.insert("tokens".to_string(), format!("{:?}", attr));
        root.children.push(AstNode {
            name: format!("#[{}]", attr.path().to_token_stream()),
            kind: "Attr".to_string(),
            span: format!("{}:{}", attr.path().span().start().line, attr.path().span().start().column),
            details,
            children: Vec::new(),
        });
    }

    stats.node_count += 1; // root
    let json = serde_json::to_string_pretty(&serde_json::json!({
        "tree": root,
        "stats": stats,
        "source_length": source.len(),
        "line_count": line_count(source),
    })).map_err(|e| format!("JSON serialization error: {}", e))?;

    Ok((json, stats))
}

fn line_count(s: &str) -> usize {
    s.lines().count()
}

fn count_nodes(node: &AstNode) -> usize {
    1 + node.children.iter().map(|c| count_nodes(c)).sum::<usize>()
}

fn source_file_name(syntax: &syn::File) -> String {
    if let Some(s) = &syntax.shebang {
        format!("source (shebang present)")
    } else {
        "source".to_string()
    }
}

fn count_item(item: &syn::Item, stats: &mut AstStats) {
    stats.item_count += 1;
    match item {
        syn::Item::Fn(_) => stats.fn_count += 1,
        syn::Item::Struct(_) => stats.struct_count += 1,
        syn::Item::Enum(_) => stats.enum_count += 1,
        syn::Item::Trait(_) => stats.trait_count += 1,
        syn::Item::Impl(_) => stats.impl_count += 1,
        _ => {}
    }
}

fn convert_item(item: &syn::Item, depth: usize) -> (AstNode, usize) {
    match item {
        syn::Item::Fn(f) => convert_fn(f, depth),
        syn::Item::Struct(s) => convert_struct(s, depth),
        syn::Item::Enum(e) => convert_enum(e, depth),
        syn::Item::Trait(t) => convert_trait(t, depth),
        syn::Item::Impl(i) => convert_impl(i, depth),
        syn::Item::Mod(m) => convert_mod(m, depth),
        syn::Item::Use(u) => convert_use(u, depth),
        syn::Item::Const(c) => convert_const(c, depth),
        syn::Item::Static(s) => convert_static(s, depth),
        syn::Item::Type(t) => convert_ty_alias(t, depth),
        syn::Item::TraitAlias(t) => convert_trait_alias(t, depth),
        syn::Item::ForeignMod(f) => convert_foreign_mod(f, depth),
        syn::Item::Macro(m) => convert_macro_item(m, depth),
        syn::Item::Verbatim(tokens) => {
            let mut d = HashMap::new();
            d.insert("tokens".to_string(), format!("{}", tokens));
            (AstNode {
                name: "<verbatim>".to_string(),
                kind: "Verbatim".to_string(),
                span: "?".to_string(),
                details: d,
                children: Vec::new(),
            }, depth)
        }
        _ => {
            let mut d = HashMap::new();
            d.insert("kind".to_string(), format!("{:?}", std::mem::discriminant(item)));
            (AstNode {
                name: format!("<unknown item>"),
                kind: "OtherItem".to_string(),
                span: "?".to_string(),
                details: d,
                children: Vec::new(),
            }, depth)
        }
    }
}

fn convert_fn(f: &syn::ItemFn, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&f.vis));
    details.insert("async".to_string(), if f.sig.asyncness.is_some() { "yes".to_string() } else { "no".to_string() });
    details.insert("unsafe".to_string(), if f.sig.unsafety.is_some() { "yes".to_string() } else { "no".to_string() });
    details.insert("abi".to_string(), f.sig.abi.as_ref().map(|a| a.name().unwrap_or("C").to_string()).unwrap_or("Rust".to_string()));

    let span = format!("{}:{}", f.sig.ident.span().start().line, f.sig.ident.span().start().column);
    let mut children = Vec::new();

    // Inputs
    for input in &f.sig.inputs {
        let (child, cd) = convert_fn_arg(input, depth + 1);
        children.push(child);
    }

    // Output
    if !is_unit_return(&f.sig.output) {
        children.push(AstNode {
            name: format!("-> {}", type_string(&f.sig.output)),
            kind: "ReturnType".to_string(),
            span: span.clone(),
            details: HashMap::new(),
            children: Vec::new(),
        });
    }

    // Generics
    for param in &f.sig.generics.params {
        let mut d = HashMap::new();
        d.insert("param".to_string(), format!("{:?}", param));
        children.push(AstNode {
            name: format!("{:?}", param),
            kind: "GenericParam".to_string(),
            span: span.clone(),
            details: d,
            children: Vec::new(),
        });
    }

    // Body
    if let Some(block) = &f.block {
        children.push(convert_block(block, depth + 1));
    }

    let mut max_depth = depth;
    for c in &children {
        // We'll track depth properly in recursion
    }
    let _ = max_depth;

    (AstNode {
        name: f.sig.ident.to_string(),
        kind: "Fn".to_string(),
        span,
        details,
        children,
    }, depth + 1)
}

fn is_unit_return(output: &syn::ReturnType) -> bool {
    matches!(output, syn::ReturnType::Default)
}

fn type_string(output: &syn::ReturnType) -> String {
    match output {
        syn::ReturnType::Default => "()".to_string(),
        syn::ReturnType::Type(_, ty) => quote::quote!(#ty).to_string(),
    }
}

fn convert_fn_arg(input: &syn::FnArg, depth: usize) -> (AstNode, usize) {
    match input {
        syn::FnArg::Receiver(r) => {
            let mut d = HashMap::new();
            d.insert("reference".to_string(), if r.reference.is_some() { "yes".to_string() } else { "no".to_string() });
            d.insert("mutability".to_string(), if r.mutability.is_some() { "mut".to_string() } else { "immutable".to_string() });
            (AstNode {
                name: "self".to_string(),
                kind: "SelfParam".to_string(),
                span: format!("{}:{}", r.self_token.span.start().line, r.self_token.span.start().column),
                details: d,
                children: Vec::new(),
            }, depth + 1)
        }
        syn::FnArg::Typed(pat_type) => {
            let name = pat_type.pat.as_ref().map(|p| quote::quote!(#p).to_string()).unwrap_or("_".to_string());
            let ty = quote::quote!(#pat_type.ty).to_string();
            let mut d = HashMap::new();
            d.insert("type".to_string(), ty);
            (AstNode {
                name,
                kind: "FnArg".to_string(),
                span: format!("{}", pat_type.ty.span().start().line),
                details: d,
                children: Vec::new(),
            }, depth + 1)
        }
    }
}

fn convert_block(block: &syn::Block, depth: usize) -> AstNode {
    let mut children = Vec::new();
    let mut max_cd = depth;
    for stmt in &block.stmts {
        let (child, cd) = convert_stmt(stmt, depth + 1);
        max_cd = max_cd.max(cd);
        children.push(child);
    }
    drop(max_cd);
    AstNode {
        name: format!("{{ ... }} ({} stmts)", block.stmts.len()),
        kind: "Block".to_string(),
        span: format!("{}:{}", block.brace_token.span.start().line, block.brace_token.span.start().column),
        details: HashMap::new(),
        children,
    }
}

fn convert_stmt(stmt: &syn::Stmt, depth: usize) -> (AstNode, usize) {
    match stmt {
        syn::Stmt::Local(local) => {
            let name = local.pat.as_ref().map(|p| quote::quote!(#p).to_string()).unwrap_or("_".to_string());
            let mut d = HashMap::new();
            if let Some(init) = &local.init {
                d.insert("init".to_string(), quote::quote!(#init.1).to_string());
            }
            (AstNode {
                name,
                kind: "Local".to_string(),
                span: format!("{}", local.pat.span().start().line),
                details: d,
                children: Vec::new(),
            }, depth)
        }
        syn::Stmt::Item(item) => convert_item(item, depth),
        syn::Stmt::Expr(expr, _) => {
            let (node, cd) = convert_expr(expr, depth);
            (node, cd)
        }
        syn::Stmt::Macro(mac) => {
            let mut d = HashMap::new();
            d.insert("mac".to_string(), quote::quote!(#mac).to_string());
            (AstNode {
                name: format!("{}!", mac.mac.path.to_token_stream()),
                kind: "MacroStmt".to_string(),
                span: format!("{}", mac.mac.path.span().start().line),
                details: d,
                children: Vec::new(),
            }, depth)
        }
    }
}

fn convert_expr(expr: &syn::Expr, depth: usize) -> (AstNode, usize) {
    match expr {
        syn::Expr::Call(call) => {
            let mut children = Vec::new();
            children.push(AstNode {
                name: format!("callee: {}", quote::quote!(#call.func)),
                kind: "CallTarget".to_string(),
                span: format!("{}", call.func.span().start().line),
                details: HashMap::new(),
                children: Vec::new(),
            });
            for arg in &call.args {
                let (child, _) = convert_expr(arg, depth + 2);
                children.push(child);
            }
            let mut d = HashMap::new();
            d.insert("args".to_string(), call.args.len().to_string());
            (AstNode {
                name: format!("{}()", quote::quote!(#call.func)),
                kind: "Call".to_string(),
                span: format!("{}", call.func.span().start().line),
                details: d,
                children,
            }, depth + 1)
        }
        syn::Expr::MethodCall(mc) => {
            let mut children = Vec::new();
            let (receiver, _) = convert_expr(&mc.receiver, depth + 2);
            children.push(receiver);
            for arg in &mc.args {
                let (child, _) = convert_expr(arg, depth + 2);
                children.push(child);
            }
            (AstNode {
                name: format!(".{}()", mc.method),
                kind: "MethodCall".to_string(),
                span: format!("{}", mc.method.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Binary(bin) => {
            let mut children = Vec::new();
            let (l, _) = convert_expr(&bin.left, depth + 2);
            let (r, _) = convert_expr(&bin.right, depth + 2);
            children.push(l);
            children.push(r);
            (AstNode {
                name: format!("{:?}", bin.op),
                kind: "BinaryOp".to_string(),
                span: format!("{}", bin.left.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Lit(lit) => {
            let mut d = HashMap::new();
            d.insert("lit".to_string(), format!("{:?}", lit.lit));
            (AstNode {
                name: format!("{:?}", lit.lit),
                kind: "Literal".to_string(),
                span: format!("{}", lit.lit.span().start().line),
                details: d,
                children: Vec::new(),
            }, depth)
        }
        syn::Expr::Path(path) => {
            let mut d = HashMap::new();
            d.insert("path".to_string(), quote::quote!(#path).to_string());
            (AstNode {
                name: quote::quote!(#path).to_string(),
                kind: "Path".to_string(),
                span: format!("{}", path.path.segments.first().map(|s| s.ident.span().start().line).unwrap_or(0)),
                details: d,
                children: Vec::new(),
            }, depth)
        }
        syn::Expr::Let(let_expr) => {
            let mut children = Vec::new();
            let (init, _) = convert_expr(&let_expr.expr, depth + 2);
            children.push(init);
            (AstNode {
                name: format!("let {} = ...", quote::quote!(#let_expr.pat)),
                kind: "LetExpr".to_string(),
                span: format!("{}", let_expr.pat.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::If(if_expr) => {
            let mut children = Vec::new();
            let (cond, _) = convert_expr(&if_expr.cond, depth + 2);
            children.push(cond);
            children.push(convert_block(&if_expr.then_branch, depth + 1));
            if let Some((_, else_expr)) = &if_expr.else_branch {
                let (else_node, _) = convert_expr(else_expr, depth + 1);
                children.push(else_node);
            }
            (AstNode {
                name: "if".to_string(),
                kind: "If".to_string(),
                span: format!("{}", if_expr.if_token.span.start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::While(while_expr) => {
            let mut children = Vec::new();
            let (cond, _) = convert_expr(&while_expr.cond, depth + 2);
            children.push(cond);
            children.push(convert_block(&while_expr.body, depth + 1));
            (AstNode {
                name: "while".to_string(),
                kind: "While".to_string(),
                span: format!("{}", while_expr.while_token.span.start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::ForLoop(for_expr) => {
            let mut children = Vec::new();
            children.push(AstNode {
                name: quote::quote!(#for_expr.pat).to_string(),
                kind: "ForPattern".to_string(),
                span: format!("{}", for_expr.pat.span().start().line),
                details: HashMap::new(),
                children: Vec::new(),
            });
            let (iter, _) = convert_expr(&for_expr.expr, depth + 2);
            children.push(iter);
            children.push(convert_block(&for_expr.body, depth + 1));
            (AstNode {
                name: "for".to_string(),
                kind: "ForLoop".to_string(),
                span: format!("{}", for_expr.for_token.span.start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Match(match_expr) => {
            let mut children = Vec::new();
            let (discriminant, _) = convert_expr(&match_expr.expr, depth + 2);
            children.push(discriminant);
            for arm in &match_expr.arms {
                let mut arm_children = Vec::new();
                let (body, _) = convert_expr(&arm.body, depth + 2);
                arm_children.push(body);
                children.push(AstNode {
                    name: format!("{:?} => ...", arm.pat),
                    kind: "MatchArm".to_string(),
                    span: format!("{}", arm.pat.span().start().line),
                    details: HashMap::new(),
                    children: arm_children,
                });
            }
            (AstNode {
                name: "match".to_string(),
                kind: "Match".to_string(),
                span: format!("{}", match_expr.match_token.span.start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Closure(closure) => {
            let mut children = Vec::new();
            let (body, _) = convert_expr(&closure.body, depth + 2);
            children.push(body);
            (AstNode {
                name: format!("|{}| ...", closure.inputs.iter().map(|a| quote::quote!(#a).to_string()).collect::<Vec<_>>().join(", ")),
                kind: "Closure".to_string(),
                span: format!("{}", closure.inputs.first().map(|a| a.span().start().line).unwrap_or(0)),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Unary(unary) => {
            let mut children = Vec::new();
            let (operand, _) = convert_expr(&unary.expr, depth + 2);
            children.push(operand);
            (AstNode {
                name: format!("{:?}", unary.op),
                kind: "UnaryOp".to_string(),
                span: format!("{}", unary.expr.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Tuple(tup) => {
            let mut children = Vec::new();
            for elem in &tup.elems {
                let (child, _) = convert_expr(elem, depth + 2);
                children.push(child);
            }
            (AstNode {
                name: format!("({})", tup.elems.len()),
                kind: "Tuple".to_string(),
                span: format!("{}", tup.elems.first().map(|e| e.span().start().line).unwrap_or(0)),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Block(block_expr) => {
            let node = convert_block(&block_expr.block, depth);
            (node, depth + 1)
        }
        syn::Expr::Return(ret) => {
            let mut children = Vec::new();
            if let Some(expr) = &ret.expr {
                let (child, _) = convert_expr(expr, depth + 2);
                children.push(child);
            }
            (AstNode {
                name: "return".to_string(),
                kind: "Return".to_string(),
                span: format!("{}", ret.return_token.span.start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Assign(assign) => {
            let mut children = Vec::new();
            let (l, _) = convert_expr(&assign.left, depth + 2);
            let (r, _) = convert_expr(&assign.right, depth + 2);
            children.push(l);
            children.push(r);
            (AstNode {
                name: "=".to_string(),
                kind: "Assign".to_string(),
                span: format!("{}", assign.left.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::AssignOp(aop) => {
            let mut children = Vec::new();
            let (l, _) = convert_expr(&aop.left, depth + 2);
            let (r, _) = convert_expr(&aop.right, depth + 2);
            children.push(l);
            children.push(r);
            (AstNode {
                name: format!("{:?}=", aop.op),
                kind: "AssignOp".to_string(),
                span: format!("{}", aop.left.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Struct(expr_struct) => {
            let mut children = Vec::new();
            for field in &expr_struct.fields {
                children.push(AstNode {
                    name: field.member.to_token_stream().to_string(),
                    kind: "FieldInit".to_string(),
                    span: format!("{}", field.member.span().start().line),
                    details: HashMap::new(),
                    children: Vec::new(),
                });
            }
            (AstNode {
                name: quote::quote!(#expr_struct.path).to_string(),
                kind: "StructExpr".to_string(),
                span: format!("{}", expr_struct.path.segments.first().map(|s| s.ident.span().start().line).unwrap_or(0)),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Field(field_expr) => {
            let mut children = Vec::new();
            let (base, _) = convert_expr(&field_expr.base, depth + 2);
            children.push(base);
            (AstNode {
                name: field_expr.member.to_token_stream().to_string(),
                kind: "FieldAccess".to_string(),
                span: format!("{}", field_expr.member.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Index(index_expr) => {
            let mut children = Vec::new();
            let (base, _) = convert_expr(&index_expr.expr, depth + 2);
            let (idx, _) = convert_expr(&index_expr.index, depth + 2);
            children.push(base);
            children.push(idx);
            (AstNode {
                name: "[]".to_string(),
                kind: "Index".to_string(),
                span: format!("{}", index_expr.expr.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Macro(mac) => {
            let mut d = HashMap::new();
            d.insert("mac".to_string(), quote::quote!(#mac).to_string());
            (AstNode {
                name: format!("{}!", mac.mac.path.to_token_stream()),
                kind: "MacroExpr".to_string(),
                span: format!("{}", mac.mac.path.span().start().line),
                details: d,
                children: Vec::new(),
            }, depth)
        }
        syn::Expr::Reference(ref_expr) => {
            let mut children = Vec::new();
            let (operand, _) = convert_expr(&ref_expr.expr, depth + 2);
            children.push(operand);
            let prefix = if ref_expr.mutability.is_some() { "&mut " } else { "&" };
            (AstNode {
                name: prefix.to_string(),
                kind: "Reference".to_string(),
                span: format!("{}", ref_expr.expr.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Await(await_expr) => {
            let mut children = Vec::new();
            let (base, _) = convert_expr(&await_expr.base, depth + 2);
            children.push(base);
            (AstNode {
                name: ".await".to_string(),
                kind: "Await".to_string(),
                span: format!("{}", await_expr.base.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Try(try_expr) => {
            let mut children = Vec::new();
            let (base, _) = convert_expr(&try_expr.expr, depth + 2);
            children.push(base);
            (AstNode {
                name: "?".to_string(),
                kind: "Try".to_string(),
                span: format!("{}", try_expr.expr.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Cast(cast) => {
            let mut children = Vec::new();
            let (base, _) = convert_expr(&cast.expr, depth + 2);
            children.push(base);
            children.push(AstNode {
                name: quote::quote!(#cast.ty).to_string(),
                kind: "CastType".to_string(),
                span: format!("{}", cast.ty.span().start().line),
                details: HashMap::new(),
                children: Vec::new(),
            });
            (AstNode {
                name: "as".to_string(),
                kind: "Cast".to_string(),
                span: format!("{}", cast.expr.span().start().line),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Array(arr) => {
            let mut children = Vec::new();
            for elem in &arr.elems {
                let (child, _) = convert_expr(elem, depth + 2);
                children.push(child);
            }
            (AstNode {
                name: format!("[{}]", arr.elems.len()),
                kind: "Array".to_string(),
                span: format!("{}", arr.elems.first().map(|e| e.span().start().line).unwrap_or(0)),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Range(range) => {
            let mut children = Vec::new();
            if let Some(start) = &range.start {
                let (child, _) = convert_expr(start, depth + 2);
                children.push(child);
            }
            if let Some(end) = &range.end {
                let (child, _) = convert_expr(end, depth + 2);
                children.push(child);
            }
            (AstNode {
                name: format!("{:?}", range.limits),
                kind: "Range".to_string(),
                span: format!("{}", range.start.as_ref().map(|s| s.span().start().line).unwrap_or(0)),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Break(brk) => {
            let mut children = Vec::new();
            if let Some(expr) = &brk.expr {
                let (child, _) = convert_expr(expr, depth + 2);
                children.push(child);
            }
            (AstNode {
                name: "break".to_string(),
                kind: "Break".to_string(),
                span: "?".to_string(),
                details: HashMap::new(),
                children,
            }, depth + 1)
        }
        syn::Expr::Continue(cont) => {
            (AstNode {
                name: "continue".to_string(),
                kind: "Continue".to_string(),
                span: "?".to_string(),
                details: HashMap::new(),
                children: Vec::new(),
            }, depth)
        }
        syn::Expr::Paren(paren) => {
            let (inner, _) = convert_expr(&paren.expr, depth + 1);
            (inner, depth + 1)
        }
        syn::Expr::Group(group) => {
            let (inner, _) = convert_expr(&group.expr, depth + 1);
            (inner, depth + 1)
        }
        _ => {
            let mut d = HashMap::new();
            d.insert("debug".to_string(), format!("{:?}", expr));
            (AstNode {
                name: format!("<{:?}>", std::mem::discriminant(expr)),
                kind: "OtherExpr".to_string(),
                span: "?".to_string(),
                details: d,
                children: Vec::new(),
            }, depth)
        }
    }
}

fn convert_struct(s: &syn::ItemStruct, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&s.vis));
    let mut children = Vec::new();
    for field in &s.fields {
        let mut d = HashMap::new();
        d.insert("type".to_string(), quote::quote!(#field.ty).to_string());
        d.insert("visibility".to_string(), vis_string(&field.vis));
        children.push(AstNode {
            name: field.ident.as_ref().map(|i| i.to_string()).unwrap_or("_".to_string()),
            kind: "Field".to_string(),
            span: format!("{}", field.ident.as_ref().map(|i| i.span().start().line).unwrap_or(0)),
            details: d,
            children: Vec::new(),
        });
    }
    (AstNode {
        name: s.ident.to_string(),
        kind: "Struct".to_string(),
        span: format!("{}:{}", s.ident.span().start().line, s.ident.span().start().column),
        details,
        children,
    }, depth + 1)
}

fn convert_enum(e: &syn::ItemEnum, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&e.vis));
    let mut children = Vec::new();
    for variant in &e.variants {
        let mut d = HashMap::new();
        d.insert("discriminant".to_string(), variant.discriminant.as_ref().map(|(_, e)| quote::quote!(#e).to_string()).unwrap_or("auto".to_string()));
        children.push(AstNode {
            name: variant.ident.to_string(),
            kind: "Variant".to_string(),
            span: format!("{}", variant.ident.span().start().line),
            details: d,
            children: Vec::new(),
        });
    }
    (AstNode {
        name: e.ident.to_string(),
        kind: "Enum".to_string(),
        span: format!("{}:{}", e.ident.span().start().line, e.ident.span().start().column),
        details,
        children,
    }, depth + 1)
}

fn convert_trait(t: &syn::ItemTrait, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&t.vis));
    details.insert("unsafe".to_string(), if t.unsafety.is_some() { "yes".to_string() } else { "no".to_string() });
    let mut children = Vec::new();
    for item in &t.items {
        match item {
            syn::TraitItem::Fn(m) => {
                let mut d = HashMap::new();
                d.insert("signature".to_string(), m.sig.ident.to_string());
                children.push(AstNode {
                    name: m.sig.ident.to_string(),
                    kind: "TraitFn".to_string(),
                    span: format!("{}", m.sig.ident.span().start().line),
                    details: d,
                    children: Vec::new(),
                });
            }
            syn::TraitItem::Type(ty) => {
                children.push(AstNode {
                    name: ty.ident.to_string(),
                    kind: "TraitType".to_string(),
                    span: format!("{}", ty.ident.span().start().line),
                    details: HashMap::new(),
                    children: Vec::new(),
                });
            }
            syn::TraitItem::Const(c) => {
                children.push(AstNode {
                    name: c.ident.to_string(),
                    kind: "TraitConst".to_string(),
                    span: format!("{}", c.ident.span().start().line),
                    details: HashMap::new(),
                    children: Vec::new(),
                });
            }
            _ => {}
        }
    }
    (AstNode {
        name: t.ident.to_string(),
        kind: "Trait".to_string(),
        span: format!("{}:{}", t.ident.span().start().line, t.ident.span().start().column),
        details,
        children,
    }, depth + 1)
}

fn convert_impl(i: &syn::ItemImpl, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("unsafety".to_string(), if i.unsafety.is_some() { "unsafe".to_string() } else { "safe".to_string() });
    let self_ty = quote::quote!(#i.self_ty).to_string();
    details.insert("self_ty".to_string(), self_ty);
    let trait_name = i.trait_.as_ref().map(|(_, path, _)| quote::quote!(#path).to_string()).unwrap_or("inherent".to_string());
    details.insert("trait".to_string(), trait_name);
    let mut children = Vec::new();
    for item in &i.items {
        match item {
            syn::ImplItem::Fn(m) => {
                let (child, _) = convert_fn(&syn::ItemFn {
                    attrs: m.attrs.clone(),
                    vis: syn::Visibility::Inherited,
                    sig: m.sig.clone(),
                    block: m.block.clone(),
                }, depth + 1);
                children.push(child);
            }
            syn::ImplItem::Type(ty) => {
                children.push(AstNode {
                    name: ty.ident.to_string(),
                    kind: "ImplType".to_string(),
                    span: format!("{}", ty.ident.span().start().line),
                    details: HashMap::new(),
                    children: Vec::new(),
                });
            }
            syn::ImplItem::Const(c) => {
                children.push(AstNode {
                    name: c.ident.to_string(),
                    kind: "ImplConst".to_string(),
                    span: format!("{}", c.ident.span().start().line),
                    details: HashMap::new(),
                    children: Vec::new(),
                });
            }
            _ => {}
        }
    }
    (AstNode {
        name: format!("impl {} for {}", trait_name, self_ty),
        kind: "Impl".to_string(),
        span: format!("{}:{}", i.impl_token.span.start().line, i.impl_token.span.start().column),
        details,
        children,
    }, depth + 1)
}

fn convert_mod(m: &syn::ItemMod, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&m.vis));
    details.insert("unsafe".to_string(), if m.unsafety.is_some() { "yes".to_string() } else { "no".to_string() });
    let mut children = Vec::new();
    if let Some((_, items)) = &m.content {
        for item in items {
            let (child, _) = convert_item(item, depth + 1);
            children.push(child);
        }
    }
    (AstNode {
        name: m.ident.to_string(),
        kind: "Mod".to_string(),
        span: format!("{}", m.ident.span().start().line),
        details,
        children,
    }, depth + 1)
}

fn convert_use(u: &syn::ItemUse, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&u.vis));
    (AstNode {
        name: format!("use {}", quote::quote!(#u.tree)),
        kind: "Use".to_string(),
        span: format!("{}", u.tree.span().start().line),
        details,
        children: Vec::new(),
    }, depth)
}

fn convert_const(c: &syn::ItemConst, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&c.vis));
    details.insert("type".to_string(), quote::quote!(#c.ty).to_string());
    (AstNode {
        name: c.ident.to_string(),
        kind: "Const".to_string(),
        span: format!("{}", c.ident.span().start().line),
        details,
        children: Vec::new(),
    }, depth)
}

fn convert_static(s: &syn::ItemStatic, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&s.vis));
    details.insert("mutability".to_string(), if s.mutability.is_some() { "mut".to_string() } else { "immutable".to_string() });
    details.insert("type".to_string(), quote::quote!(#s.ty).to_string());
    (AstNode {
        name: s.ident.to_string(),
        kind: "Static".to_string(),
        span: format!("{}", s.ident.span().start().line),
        details,
        children: Vec::new(),
    }, depth)
}

fn convert_ty_alias(t: &syn::ItemType, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&t.vis));
    details.insert("type".to_string(), quote::quote!(#t.ty).to_string());
    (AstNode {
        name: t.ident.to_string(),
        kind: "TypeAlias".to_string(),
        span: format!("{}", t.ident.span().start().line),
        details,
        children: Vec::new(),
    }, depth)
}

fn convert_trait_alias(t: &syn::ItemTraitAlias, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("visibility".to_string(), vis_string(&t.vis));
    (AstNode {
        name: format!("{} = {}", t.ident, quote::quote!(#t.bounds)),
        kind: "TraitAlias".to_string(),
        span: format!("{}", t.ident.span().start().line),
        details,
        children: Vec::new(),
    }, depth)
}

fn convert_foreign_mod(f: &syn::ItemForeignMod, depth: usize) -> (AstNode, usize) {
    let mut children = Vec::new();
    for item in &f.items {
        match item {
            syn::ForeignItem::Fn(ff) => {
                let mut d = HashMap::new();
                d.insert("abi".to_string(), f.abi.name().unwrap_or("C").to_string());
                children.push(AstNode {
                    name: ff.ident.to_string(),
                    kind: "ForeignFn".to_string(),
                    span: format!("{}", ff.ident.span().start().line),
                    details: d,
                    children: Vec::new(),
                });
            }
            syn::ForeignItem::Static(fs) => {
                children.push(AstNode {
                    name: fs.ident.to_string(),
                    kind: "ForeignStatic".to_string(),
                    span: format!("{}", fs.ident.span().start().line),
                    details: HashMap::new(),
                    children: Vec::new(),
                });
            }
            _ => {}
        }
    }
    (AstNode {
        name: f.abi.name().unwrap_or("extern").to_string(),
        kind: "ForeignMod".to_string(),
        span: "?".to_string(),
        details: HashMap::new(),
        children,
    }, depth + 1)
}

fn convert_macro_item(m: &syn::ItemMacro, depth: usize) -> (AstNode, usize) {
    let mut details = HashMap::new();
    details.insert("path".to_string(), m.mac.path.to_token_stream().to_string());
    (AstNode {
        name: format!("{}!", m.mac.path.to_token_stream()),
        kind: "MacroItem".to_string(),
        span: format!("{}", m.mac.path.span().start().line),
        details,
        children: Vec::new(),
    }, depth)
}

fn vis_string(vis: &syn::Visibility) -> String {
    match vis {
        syn::Visibility::Public(_) => "pub".to_string(),
        syn::Visibility::Restricted(r) => format!("pub({})", r.path.to_token_stream()),
        syn::Visibility::Inherited => "private".to_string(),
    }
}

// ===================================================================
// HTML viewer rendering
// ===================================================================

fn wrap_decl_html(id: &str, tree_json: &str, stats: &AstStats) -> String {
    format!(r#"<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Decl Tile: {id}</title>
<style>
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace; font-size: 13px; background: #1e1e2e; color: #cdd6f4; }}
.toolbar {{ position: sticky; top: 0; z-index: 100; background: #181825; padding: 8px 16px; border-bottom: 1px solid #313244; display: flex; gap: 12px; align-items: center; }}
.toolbar input {{ background: #313244; border: 1px solid #45475a; color: #cdd6f4; padding: 4px 8px; border-radius: 4px; width: 200px; outline: none; }}
.toolbar input:focus {{ border-color: #89b4fa; }}
.toolbar .stats {{ display: flex; gap: 16px; margin-left: auto; font-size: 11px; color: #6c7086; }}
.toolbar .stat {{ display: flex; align-items: center; gap: 4px; }}
.toolbar .stat .num {{ color: #89b4fa; font-weight: bold; }}
.tree-container {{ padding: 8px; overflow: auto; max-height: calc(100vh - 48px); }}
.tree-node {{ margin-left: 0; }}
.node-row {{ display: flex; align-items: center; gap: 4px; padding: 2px 4px; border-radius: 3px; cursor: pointer; white-space: nowrap; }}
.node-row:hover {{ background: #313244; }}
.node-row .toggle {{ width: 16px; text-align: center; color: #6c7086; cursor: pointer; user-select: none; flex-shrink: 0; }}
.node-row .toggle.empty {{ visibility: hidden; }}
.node-row .kind-badge {{ display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: 10px; font-weight: 600; letter-spacing: 0.5px; flex-shrink: 0; }}
.node-row .kind-fn {{ background: #cba6f7; color: #1e1e2e; }}
.node-row .kind-struct {{ background: #89b4fa; color: #1e1e2e; }}
.node-row .kind-enum {{ background: #f5c2e7; color: #1e1e2e; }}
.node-row .kind-trait {{ background: #a6e3a1; color: #1e1e2e; }}
.node-row .kind-impl {{ background: #fab387; color: #1e1e2e; }}
.node-row .kind-fnarg {{ background: #94e2d5; color: #1e1e2e; }}
.node-row .kind-call {{ background: #74c7ec; color: #1e1e2e; }}
.node-row .kind-literal {{ background: #f9e2af; color: #1e1e2e; }}
.node-row .kind-block {{ background: #45475a; color: #cdd6f4; }}
.node-row .kind-local {{ background: #585b70; color: #cdd6f4; }}
.node-row .kind-mod {{ background: #b4befe; color: #1e1e2e; }}
.node-row .kind-use {{ background: #6c7086; color: #cdd6f4; }}
.node-row .kind-const {{ background: #eba0ac; color: #1e1e2e; }}
.node-row .kind-field {{ background: #585b70; color: #cdd6f4; }}
.node-row .kind-variant {{ background: #f5c2e7; color: #1e1e2e; }}
.node-row .node-name {{ color: #cdd6f4; margin-left: 4px; }}
.node-row .node-details {{ color: #6c7086; font-size: 11px; margin-left: 8px; }}
.node-row .span-info {{ color: #585b70; font-size: 10px; margin-left: auto; }}
.children {{ margin-left: 20px; border-left: 1px solid #313244; }}
.hidden {{ display: none; }}
.error-display {{ background: #1e1e2e; color: #f38ba8; padding: 16px; white-space: pre-wrap; font-family: monospace; }}
.loading {{ padding: 20px; text-align: center; color: #6c7086; }}
</style></head><body>
<div class="toolbar">
  <span style="color:#cba6f7;font-weight:bold;">📐 Decl Tile</span>
  <input type="text" id="filter-input" placeholder="Filter nodes..." oninput="applyFilter(this.value)">
  <div class="stats">
    <span class="stat">nodes <span class="num" id="stat-nodes">{node_count}</span></span>
    <span class="stat">items <span class="num" id="stat-items">{item_count}</span></span>
    <span class="stat">fn <span class="num">{fn_count}</span></span>
    <span class="stat">struct <span class="num">{struct_count}</span></span>
    <span class="stat">enum <span class="num">{enum_count}</span></span>
    <span class="stat">trait <span class="num">{trait_count}</span></span>
    <span class="stat">impl <span class="num">{impl_count}</span></span>
  </div>
</div>
<div class="tree-container" id="tree-container">
  <div id="tree-root" class="tree-node"></div>
</div>
<script>
const AST_DATA = {tree_json};

// Render a single node
function createNode(node, depth) {{
  const wrapper = document.createElement('div');
  wrapper.className = 'tree-node';
  wrapper.dataset.name = (node.name || '').toLowerCase();
  wrapper.dataset.kind = (node.kind || '').toLowerCase();

  const row = document.createElement('div');
  row.className = 'node-row';

  // Toggle
  const toggle = document.createElement('span');
  toggle.className = 'toggle' + (node.children && node.children.length > 0 ? '' : ' empty');
  if (node.children && node.children.length > 0) {{
    toggle.textContent = '▼';
    toggle.style.cursor = 'pointer';
    toggle.onclick = function(e) {{
      e.stopPropagation();
      const children = wrapper.querySelector('.children');
      if (children) {{
        children.classList.toggle('hidden');
        toggle.textContent = children.classList.contains('hidden') ? '▶' : '▼';
      }}
    }};
  }} else {{
    toggle.textContent = ' ';
  }}
  row.appendChild(toggle);

  // Badge
  const badge = document.createElement('span');
  badge.className = 'kind-badge kind-' + (node.kind || 'other').toLowerCase();
  badge.textContent = node.kind || '?';
  row.appendChild(badge);

  // Name
  const nameSpan = document.createElement('span');
  nameSpan.className = 'node-name';
  nameSpan.textContent = node.name || '';
  row.appendChild(nameSpan);

  // Details
  if (node.details && Object.keys(node.details).length > 0) {{
    const detailSpan = document.createElement('span');
    detailSpan.className = 'node-details';
    const detailStr = Object.entries(node.details)
      .filter(([k,v]) => k !== 'kind' && k !== 'debug')
      .map(([k,v]) => k + '=' + v)
      .join(' ');
    if (detailStr) detailSpan.textContent = '[' + detailStr + ']';
    row.appendChild(detailSpan);
  }}

  // Span
  if (node.span && node.span !== '?') {{
    const spanInfo = document.createElement('span');
    spanInfo.className = 'span-info';
    spanInfo.textContent = node.span;
    row.appendChild(spanInfo);
  }}

  wrapper.appendChild(row);

  // Children
  if (node.children && node.children.length > 0) {{
    const childrenContainer = document.createElement('div');
    childrenContainer.className = 'children';
    node.children.forEach(child => {{
      childrenContainer.appendChild(createNode(child, depth + 1));
    }});
    wrapper.appendChild(childrenContainer);
  }}

  return wrapper;
}}

// Render full tree
function renderTree() {{
  const root = document.getElementById('tree-root');
  root.innerHTML = '';
  root.appendChild(createNode(AST_DATA.tree, 0));
}}

// Filter
function applyFilter(q) {{
  const term = q.toLowerCase().trim();
  document.querySelectorAll('.tree-node').forEach(node => {{
    if (!term) {{
      node.style.display = '';
      return;
    }}
    const name = node.dataset.name || '';
    const kind = node.dataset.kind || '';
    const matches = name.includes(term) || kind.includes(term);
    node.style.display = matches ? '' : 'none';
    // Also show parents of matches
    if (matches) {{
      let parent = node.parentElement ? node.parentElement.closest('.tree-node') : null;
      while (parent) {{
        parent.style.display = '';
        const childContainer = parent.querySelector('.children');
        if (childContainer) childContainer.classList.remove('hidden');
        const toggle = parent.querySelector('.toggle');
        if (toggle) toggle.textContent = '▼';
        parent = parent.parentElement ? parent.parentElement.closest('.tree-node') : null;
      }}
    }}
  }});
}}

renderTree();
</script>
</body></html>"#,
        id = id,
        tree_json = tree_json_str(&tree_json),
        node_count = stats.node_count,
        item_count = stats.item_count,
        fn_count = stats.fn_count,
        struct_count = stats.struct_count,
        enum_count = stats.enum_count,
        trait_count = stats.trait_count,
        impl_count = stats.impl_count,
    )
}

/// Helper to extract just the tree JSON from the full JSON document.
/// The full JSON has structure: {{"tree": ..., "stats": ..., ...}}
fn tree_json_str(full: &str) -> String {
    // Extract the tree portion — find the "tree": key and everything after
    if let Some(pos) = full.find(r#""tree":"#) {
        // We need the value after "tree": — which starts after position + 7
        let start = pos + 7; // skip past the key
        // Find the matching closing brace. The tree is the first top-level value.
        // Simple approach: return the "tree" property by itself
        // Actually, the JSON is: { "tree": {...}, "stats": {...}, ... }
        // We want just the tree value as a JSON string
        // Find the matching brace that closes the tree value
        if let Some(tree_start) = full[start..].find('{') {
            let tree_start_abs = start + tree_start;
            let mut depth = 0;
            for (i, ch) in full[tree_start_abs..].char_indices() {
                match ch {
                    '{' => depth += 1,
                    '}' => {
                        depth -= 1;
                        if depth == 0 {
                            let tree_str = &full[tree_start_abs..=tree_start_abs + i];
                            // Escape for embedding in JS
                            return serde_json::to_string(tree_str).unwrap_or_else(|_| "\"\"".to_string());
                        }
                    }
                    _ => {}
                }
            }
        }
    }
    // Fallback: use the full JSON wrapped in a JS object
    // Escape the full JSON for embedding in a JS string
    serde_json::to_string(full).unwrap_or_else(|_| "\"\"".to_string())
}
