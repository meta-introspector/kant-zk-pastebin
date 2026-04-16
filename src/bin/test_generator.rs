use std::collections::HashMap;

/// Generate test cases from Monster group symmetries
/// Each of 194 irreps generates a different test input

const MONSTER_PRIMES: &[u64] = &[2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 41, 47, 59, 71];

struct TestGenerator {
    irrep_idx: usize,
}

impl TestGenerator {
    fn new(irrep_idx: usize) -> Self {
        Self { irrep_idx: irrep_idx % 194 }
    }
    
    /// Generate test input from orbifold coords
    fn generate_input(&self, field: &str) -> String {
        let coords = self.coords_for_irrep();
        match field {
            "title" => format!("Test_{}", coords[0]),
            "content" => {
                let mut content = String::new();
                for i in 0..coords[1] % 100 {
                    content.push_str(&format!("Line {} ", i));
                }
                content
            }
            "tag" => format!("tag_{}", coords[2] % 10),
            _ => String::new(),
        }
    }
    
    fn coords_for_irrep(&self) -> Vec<u64> {
        MONSTER_PRIMES.iter()
            .map(|&p| (self.irrep_idx as u64 * 13) % p)
            .collect()
    }
    
    /// Generate all test cases (194 from Monster irreps)
    fn generate_all() -> Vec<TestCase> {
        (0..194).map(|i| {
            let gen = TestGenerator::new(i);
            TestCase {
                irrep: i,
                coords: gen.coords_for_irrep(),
                inputs: HashMap::from([
                    ("title".to_string(), gen.generate_input("title")),
                    ("content".to_string(), gen.generate_input("content")),
                    ("tag".to_string(), gen.generate_input("tag")),
                ]),
            }
        }).collect()
    }
}

#[derive(Debug)]
struct TestCase {
    irrep: usize,
    coords: Vec<u64>,
    inputs: HashMap<String, String>,
}

fn main() {
    println!("=== Monster Symmetry Test Generator ===\n");
    
    let test_cases = TestGenerator::generate_all();
    
    println!("Generated {} test cases from Monster irreps\n", test_cases.len());
    
    // Show first 10
    for (i, tc) in test_cases.iter().take(10).enumerate() {
        println!("Test {}: irrep={}, coords={:?}", i, tc.irrep, &tc.coords[..3]);
        println!("  title: {}", tc.inputs.get("title").unwrap());
        println!("  content: {} bytes", tc.inputs.get("content").unwrap().len());
        println!("  tag: {}", tc.inputs.get("tag").unwrap());
        println!();
    }
    
    // Output as AFL++ seed corpus
    std::fs::create_dir_all("fuzz/corpus").expect("create corpus dir");
    for (i, tc) in test_cases.iter().enumerate() {
        let json = serde_json::json!({
            "irrep": tc.irrep,
            "coords": tc.coords,
            "inputs": tc.inputs,
        });
        let path = format!("fuzz/corpus/test_{:03}.json", i);
        std::fs::write(&path, json.to_string()).expect("write seed");
    }
    
    println!("Wrote {} seed files to fuzz/corpus/", test_cases.len());
}
