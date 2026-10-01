use std::fs::File;
use std::io::Read;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("Usage: flake-lock-reader <path-to-flake.lock> [node-name]");
        std::process::exit(1);
    });
    let node_name = std::env::args().nth(2).unwrap_or_else(|| {
        eprintln!("Usage: flake-lock-reader <path-to-flake.lock> [node-name]");
        std::process::exit(1);
    });

    let mut file = File::open(&path)?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)?;

    let value: serde_json::Value = serde_json::from_str(&contents)?;

    if let Some(nodes) = value.get("nodes") {
        if let Some(node) = nodes.get(&node_name) {
            println!("Node: {}", node_name);
            println!("{}", serde_json::to_string_pretty(node)?);
        } else {
            eprintln!("Node '{}' not found in flake.lock", node_name);
            // List available nodes
            if let Some(obj) = nodes.as_object() {
                eprintln!("Available nodes:");
                for key in obj.keys() {
                    eprintln!("  - {}", key);
                }
            }
            std::process::exit(1);
        }
    } else {
        eprintln!("No 'nodes' key found in flake.lock");
        std::process::exit(1);
    }

    Ok(())
}
