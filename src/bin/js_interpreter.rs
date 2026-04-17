use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_parser::Parser;
use oxc_span::SourceType;
use std::collections::HashMap;

/// JS interpreter for dynamic website tests
struct JsInterpreter<'a> {
    allocator: &'a Allocator,
    globals: HashMap<String, JsValue>,
    trace: Vec<ExecutionStep>,
}

#[derive(Debug, Clone)]
enum JsValue {
    Undefined,
    Number(f64),
    String(String),
    Boolean(bool),
    Object(HashMap<String, JsValue>),
}

#[derive(Debug)]
struct ExecutionStep {
    coords: Vec<u64>,
    operation: String,
    value: String,
}

impl<'a> JsInterpreter<'a> {
    fn new(allocator: &'a Allocator) -> Self {
        let mut globals = HashMap::new();
        globals.insert("document".to_string(), JsValue::Object(HashMap::new()));
        globals.insert("window".to_string(), JsValue::Object(HashMap::new()));
        
        Self {
            allocator,
            globals,
            trace: vec![],
        }
    }
    
    fn execute(&mut self, source: &str) -> Result<JsValue, String> {
        let source_type = SourceType::default().with_module(false);
        let ret = Parser::new(self.allocator, source, source_type).parse();
        
        if !ret.errors.is_empty() {
            return Err(format!("Parse error: {:?}", ret.errors[0]));
        }
        
        self.eval_program(&ret.program)
    }
    
    fn eval_program(&mut self, prog: &Program) -> Result<JsValue, String> {
        let mut last = JsValue::Undefined;
        for stmt in &prog.body {
            last = self.eval_statement(stmt)?;
        }
        Ok(last)
    }
    
    fn eval_statement(&mut self, stmt: &Statement) -> Result<JsValue, String> {
        match stmt {
            Statement::ExpressionStatement(expr_stmt) => {
                self.eval_expression(&expr_stmt.expression)
            }
            Statement::VariableDeclaration(decl) => {
                for declarator in &decl.declarations {
                    if let Some(init) = &declarator.init {
                        let value = self.eval_expression(init)?;
                        if let BindingPattern::BindingIdentifier(id) = &declarator.id {
                            let coords = erdfa_dasl::orbifold_coords_full(id.span.start as usize);
                            self.trace.push(ExecutionStep {
                                coords: coords[..3].to_vec(),
                                operation: "var_decl".to_string(),
                                value: format!("{:?}", value),
                            });
                            self.globals.insert(id.name.to_string(), value);
                        }
                    }
                }
                Ok(JsValue::Undefined)
            }
            _ => Ok(JsValue::Undefined),
        }
    }
    
    fn eval_expression(&mut self, expr: &Expression) -> Result<JsValue, String> {
        match expr {
            Expression::NumericLiteral(lit) => Ok(JsValue::Number(lit.value)),
            Expression::StringLiteral(lit) => Ok(JsValue::String(lit.value.to_string())),
            Expression::BooleanLiteral(lit) => Ok(JsValue::Boolean(lit.value)),
            Expression::Identifier(id) => {
                self.globals.get(id.name.as_str())
                    .cloned()
                    .ok_or_else(|| format!("Undefined: {}", id.name))
            }
            Expression::CallExpression(call) => {
                let coords = erdfa_dasl::orbifold_coords_full(call.span.start as usize);
                self.trace.push(ExecutionStep {
                    coords: coords[..3].to_vec(),
                    operation: "call".to_string(),
                    value: "function()".to_string(),
                });
                Ok(JsValue::Undefined)
            }
            _ => Ok(JsValue::Undefined),
        }
    }
    
    fn get_trace(&self) -> &[ExecutionStep] {
        &self.trace
    }
}

fn main() {
    println!("=== JS Interpreter Tests ===\n");
    
    let allocator = Allocator::default();
    let mut interp = JsInterpreter::new(&allocator);
    
    // Test 1: Variable declaration
    println!("1. Variable Declaration");
    let result = interp.execute("var x = 42;");
    println!("   Result: {:?}", result);
    
    // Test 2: String literal
    println!("\n2. String Literal");
    let result = interp.execute("var msg = 'hello';");
    println!("   Result: {:?}", result);
    
    // Test 3: Function call
    println!("\n3. Function Call");
    let result = interp.execute("console.log('test');");
    println!("   Result: {:?}", result);
    
    // Show execution trace
    println!("\n=== Execution Trace ===");
    for (i, step) in interp.get_trace().iter().enumerate() {
        println!("{}. {} at coords {:?} = {}", 
            i + 1, step.operation, step.coords, step.value);
    }
}
