use std::io::{self, Read};
use zos_core03::{verify_frame, Outcome, MAX_FRAME};

fn main() {
    let mut frame = Vec::new();
    let result = match io::stdin()
        .take((MAX_FRAME + 1) as u64)
        .read_to_end(&mut frame)
    {
        Ok(_) => verify_frame(&frame),
        Err(_) => Outcome::Indeterminate,
    };
    println!("{}", result as u32);
}
