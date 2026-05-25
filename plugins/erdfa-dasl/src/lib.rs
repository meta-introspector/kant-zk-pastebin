//! erdfa-dasl: core DASL types and traits
//! OrbifoldCoords is N-dimensional (Vec<u64>) not fixed 3-tuple

pub use crate::dasl::*;

mod dasl;

/// N-dimensional orbifold coordinates in Monster prime lattice
pub type OrbifoldCoords = Vec<u64>;

/// Trait for content-addressable objects
pub trait DaslAddressable {
    fn dasl_cid(&self) -> u64;
    fn orbifold(&self) -> OrbifoldCoords;
}
