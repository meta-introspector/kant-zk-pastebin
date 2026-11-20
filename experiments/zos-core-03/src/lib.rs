use ed25519_dalek::{Signature as Ed25519Signature, VerifyingKey};
use sha2::{Digest, Sha256};

const DESCRIPTOR: &str = include_str!("../inputs/descriptor.txt");
const CANONICAL: &[u8] = concat!(
    "zos.core01b.receipt.v1\nverdict=accepted\nbasis=source-compiled-jobverifier-fixture\n",
    include_str!("../inputs/descriptor.txt"),
)
.as_bytes();
const OPERATION: &[u8] = b"treasury:debit:7";
const LIMITS: [usize; 5] = [4096, 64, 32, 1_048_576, 64];
pub const MAX_FRAME: usize = 20 + LIMITS[0] + LIMITS[1] + LIMITS[2] + LIMITS[3] + LIMITS[4];

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Outcome {
    Authenticated = 1,
    Malformed = 2,
    Limit = 3,
    Signature = 4,
    Descriptor = 5,
    Artifact = 6,
    Operation = 7,
    Indeterminate = 8,
}

pub fn verify_frame(mut input: &[u8]) -> Outcome {
    use Outcome::*;
    if input.len() > MAX_FRAME {
        return Limit;
    }

    let mut fields = [&[][..]; 5];
    for (field, limit) in fields.iter_mut().zip(LIMITS) {
        let Some((length, remaining)) = input.split_first_chunk::<4>() else {
            return Malformed;
        };
        let size = u32::from_le_bytes(*length) as usize;
        if size > limit {
            return Limit;
        }
        let Some((value, remaining)) = remaining.split_at_checked(size) else {
            return Malformed;
        };
        *field = value;
        input = remaining;
    }
    let [message, signature, key, artifact, operation] = fields;
    if !input.is_empty() {
        return Malformed;
    }
    let (Ok(key), Ok(signature)) = (
        <&[u8; 32]>::try_from(key),
        Ed25519Signature::from_slice(signature),
    ) else {
        return Malformed;
    };
    let Ok(key) = VerifyingKey::from_bytes(key) else {
        return Signature;
    };
    if key.verify_strict(message, &signature).is_err() {
        return Signature;
    }
    if message != CANONICAL {
        return Descriptor;
    }
    if operation != OPERATION {
        return Operation;
    }
    let Some(digest) = DESCRIPTOR
        .lines()
        .find_map(|line| line.strip_prefix("artifact-sha256="))
    else {
        return Indeterminate;
    };
    let hex = b"0123456789abcdef";
    let hash = Sha256::digest(artifact);
    if !hash
        .iter()
        .flat_map(|byte| [hex[(byte >> 4) as usize], hex[(byte & 15) as usize]])
        .eq(digest.bytes())
    {
        return Artifact;
    }
    Authenticated
}

#[cfg(target_arch = "wasm32")]
mod wasm {
    use super::*;
    // The import-free instance has one synchronous caller and no shared memory.
    // The host writes the frame into this exported staging region between calls.
    static mut FRAME: [u8; MAX_FRAME] = [0; MAX_FRAME];

    #[no_mangle]
    pub extern "C" fn frame_ptr() -> *mut u8 {
        (&raw mut FRAME).cast()
    }

    #[no_mangle]
    pub extern "C" fn frame_capacity() -> usize {
        MAX_FRAME
    }

    #[no_mangle]
    pub extern "C" fn verify(length: usize) -> u32 {
        if length > MAX_FRAME {
            return Outcome::Limit as u32;
        }
        // The checked slice stays within FRAME and cannot outlive this call.
        let frame = unsafe { std::slice::from_raw_parts(frame_ptr(), length) };
        verify_frame(frame) as u32
    }
}
