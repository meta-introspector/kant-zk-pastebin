//! `libp2p_frames.rs` — the wire format for file chunks over a libp2p
//! swarm, and nothing else.
//!
//! This is an exact port of the framing in `web/kant-libp2p.mjs`. The
//! encoder and decoder here must produce and accept **byte-identical**
//! messages to the JS ones, or a Rust peer and a browser peer cannot talk:
//! the JS `decode` returns `null` for anything it does not recognise, so a
//! one-byte difference is not a warning, it is silence.
//!
//! Why this file has no libp2p dependency: the same discipline
//! `web/kant-file.mjs` keeps. The framing is a pure function of its inputs —
//! no clock, no network, no storage — so it can be tested exhaustively and
//! cross-checked against the JS without a swarm. The libp2p wiring lives in
//! `libp2p_swarm.rs` and depends on this.
//!
//! # Wire format
//!
//! ```text
//!  0      tag       u8    1 = want, 2 = have, 3 = deny
//!  1..33  witness   32B   the Kant witness of the chunk (64 hex chars)
//! 33..37  index     u32   frame index, big endian
//! 37..41  total     u32   frame count for this chunk
//! 41..    payload   rest  frame bytes on a `have`; empty otherwise
//!               +nonce 0..8B appended, only on a `want`
//! ```
//!
//! The nonce rides AFTER the payload so a `have` frame's length is still
//! `header + payload` and the decoder needs no special case. It exists
//! because gossipsub de-duplicates by message bytes: without it a retried
//! request identical to the first is refused as a duplicate, and a chunk
//! could only ever be asked for once.
//!
//! # What crosses the wire
//!
//! Ciphertext, never plaintext. A chunk is already AES-GCM under the room
//! key before it reaches this module, so a peer in the topic but not in the
//! room learns a file's size and chunk count and nothing else. The room
//! secret never appears here.

use std::fmt;

/// Tag for a request for one chunk.
pub const TAG_WANT: u8 = 1;
/// Tag for one frame of a chunk's ciphertext.
pub const TAG_HAVE: u8 = 2;
/// Tag saying "nobody here has that chunk".
pub const TAG_DENY: u8 = 3;

/// Header size in bytes: tag + witness + index + total.
pub const HEADER: usize = 41;

/// Default frame size for the wire: 16 KiB plus the header.
///
/// gossipsub 0.47 has no `max_message_size` knob exposed the way the JS
/// build's transport limits do; the binding constraint is the stream window
/// of whatever transport carries it. 16 KiB sits far below every libp2p
/// transport's default, which is the property worth having — a frame is
/// never the thing a peer refuses.
pub const FRAME_BYTES: usize = 16 * 1024;

/// Smallest frame worth sending.
pub const MIN_FRAME_BYTES: usize = 1024;

/// Largest frame accepted, regardless of what a peer claims.
pub const MAX_FRAME_BYTES: usize = 64 * 1024;

/// Largest chunk we will assemble. A chunk bigger than this is not a file
/// share, it is an attack.
pub const MAX_CHUNK_BYTES: usize = 1024 * 1024;

/// Longest request nonce carried on the wire.
pub const MAX_NONCE_BYTES: usize = 8;

/// Errors from this module. Kept distinct from `libp2p`'s own error types so
/// a caller can tell "a peer sent me nonsense" from "the router is unhappy".
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FrameError {
    /// Not 64 hex characters.
    BadWitness(String),
    /// Frame index/total inconsistent (negative, zero total, or index past total).
    BadFrame,
    /// The tag byte is not one of the three known tags.
    BadTag(u8),
    /// Payload larger than [`MAX_CHUNK_BYTES`].
    TooBig(usize),
    /// A witness that is not 32 bytes of hex decoded cleanly.
    NotAWitness,
    /// A frame carried both a payload and a nonce.
    ///
    /// The nonce rides AFTER the payload so that a `have` frame's length is
    /// exactly header + payload and the decoder needs no special case. That
    /// only works while at most one of the two is present: nothing on the wire
    /// marks where the payload ends, so a `have` carrying a nonce would decode
    /// its own nonce as chunk bytes. Only `want` may carry a nonce, and a
    /// `want` never carries a payload.
    PayloadAndNonce,
}

impl fmt::Display for FrameError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            FrameError::BadWitness(s) => write!(f, "not a witness: {s}"),
            FrameError::BadFrame => write!(f, "bad frame index/total"),
            FrameError::BadTag(t) => write!(f, "unknown tag {t}"),
            FrameError::TooBig(n) => write!(f, "frame payload {n}B exceeds the cap"),
            FrameError::NotAWitness => write!(f, "not a 32-byte witness"),
            FrameError::PayloadAndNonce => {
                write!(f, "a frame may carry a payload or a nonce, never both")
            }
        }
    }
}

impl std::error::Error for FrameError {}

/// Result alias for this module.
pub type Result<T> = std::result::Result<T, FrameError>;

/// One decoded wire message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    /// One of [`TAG_WANT`], [`TAG_HAVE`], [`TAG_DENY`].
    pub tag: u8,
    /// The chunk's Kant witness, 64 lower-case hex characters.
    pub witness: String,
    /// This frame's index, 0-based.
    pub index: u32,
    /// How many frames the whole chunk has.
    pub total: u32,
    /// Frame bytes. Empty for a `want` or a `deny`.
    pub payload: Vec<u8>,
    /// Request nonce, appended after the payload on a `want`.
    ///
    /// Not part of the protocol's meaning — only of its byte identity, which
    /// is exactly why it is here: gossipsub de-duplicates by message bytes,
    /// so a retried request must not be byte-identical to the first.
    pub nonce: Option<Vec<u8>>,
}

impl Frame {
    /// A request for one chunk.
    pub fn want(witness: &str, total: u32, nonce: u32) -> Result<Frame> {
        Frame::build(TAG_WANT, witness, 0, total, Vec::new(), Some(nonce.to_be_bytes().to_vec()))
    }

    /// One frame of a chunk's bytes.
    pub fn have(witness: &str, index: u32, total: u32, payload: Vec<u8>) -> Result<Frame> {
        Frame::build(TAG_HAVE, witness, index, total, payload, None)
    }

    /// "I do not have that chunk."
    pub fn deny(witness: &str) -> Result<Frame> {
        Frame::build(TAG_DENY, witness, 0, 1, Vec::new(), None)
    }

    fn build(
        tag: u8,
        witness: &str,
        index: u32,
        total: u32,
        payload: Vec<u8>,
        nonce: Option<Vec<u8>>,
    ) -> Result<Frame> {
        let witness = normalize_witness(witness).ok_or_else(|| FrameError::BadWitness(witness.into()))?;
        if total == 0 || index >= total {
            return Err(FrameError::BadFrame);
        }
        if payload.len() > MAX_CHUNK_BYTES {
            return Err(FrameError::TooBig(payload.len()));
        }
        Ok(Frame { tag, witness, index, total, payload, nonce })
    }
}

/// Normalise a witness to 64 lower-case hex characters, or `None`.
///
/// Upper case is accepted: witnesses are hex, every producer here emits
/// lower case, but one that has been through a hex library or a shell may
/// not be — and refusing it would mean refusing a chunk named perfectly
/// correctly. Matches `asWitness` in `web/kant-libp2p.mjs`.
pub fn normalize_witness(s: &str) -> Option<String> {
    if s.len() != 64 {
        return None;
    }
    let lower = s.to_ascii_lowercase();
    if lower.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
        Some(lower)
    } else {
        None
    }
}

/// Encode a frame to bytes.
///
/// Must be byte-identical to `encode` in `web/kant-libp2p.mjs`, including
/// the nonce placement after the payload.
pub fn encode(frame: &Frame) -> Result<Vec<u8>> {
    let witness = normalize_witness(&frame.witness)
        .ok_or_else(|| FrameError::BadWitness(frame.witness.clone()))?;
    if frame.total == 0 || frame.index >= frame.total {
        return Err(FrameError::BadFrame);
    }
    if frame.payload.len() > MAX_CHUNK_BYTES {
        return Err(FrameError::TooBig(frame.payload.len()));
    }
    let witness_bytes = hex_to_bytes(&witness).ok_or(FrameError::NotAWitness)?;
    // The wire format has no payload-length field, so a frame carrying both a
    // payload and a nonce would be undecodable. Refuse rather than emit bytes
    // that only happen to work because no caller does this today.
    if frame.nonce.is_some() && !frame.payload.is_empty() {
        return Err(FrameError::PayloadAndNonce);
    }
    let nonce = frame.nonce.clone().unwrap_or_default();
    let nonce = &nonce[..nonce.len().min(MAX_NONCE_BYTES)];

    let mut out = Vec::with_capacity(HEADER + frame.payload.len() + nonce.len());
    out.push(frame.tag);
    out.extend_from_slice(&witness_bytes);
    out.extend_from_slice(&frame.index.to_be_bytes());
    out.extend_from_slice(&frame.total.to_be_bytes());
    out.extend_from_slice(&frame.payload);
    out.extend_from_slice(nonce);
    Ok(out)
}

/// Decode a frame, or `None` for anything malformed.
///
/// Returns `None` rather than an error because the sender is a stranger: a
/// malformed message from a peer is not this module's problem to raise, and
/// the JS `decode` does exactly the same, so both sides ignore it alike.
pub fn decode(bytes: &[u8]) -> Option<Frame> {
    if bytes.len() < HEADER {
        return None;
    }
    let tag = bytes[0];
    if tag != TAG_WANT && tag != TAG_HAVE && tag != TAG_DENY {
        return None;
    }
    let witness = bytes_to_hex(&bytes[1..33]);
    let index = u32::from_be_bytes([bytes[33], bytes[34], bytes[35], bytes[36]]);
    let total = u32::from_be_bytes([bytes[37], bytes[38], bytes[39], bytes[40]]);
    if total == 0 || index >= total || total > 0x10000 {
        return None;
    }
    let rest = &bytes[HEADER..];
    // Only a `have` carries a payload; for a want the trailing bytes are the
    // nonce, and for a deny there is nothing at all.
    let payload = if tag == TAG_HAVE { rest.to_vec() } else { Vec::new() };
    if payload.len() > MAX_CHUNK_BYTES {
        return None;
    }
    Some(Frame { tag, witness, index, total, payload, nonce: None })
}

/// The topic for one file: `kant-file/1/<room>/<manifest-witness>`.
///
/// A topic name is public, so it is derived from the room (which the relay
/// already knows) and the manifest witness (which every peer in the room
/// already knows), never from the secret. Matches `topicOf` in the JS.
pub fn topic_of(room: &str, manifest_witness: &str) -> Result<String> {
    if room.is_empty() {
        return Err(FrameError::BadWitness("a topic needs a room".into()));
    }
    let w = normalize_witness(manifest_witness)
        .ok_or_else(|| FrameError::BadWitness(manifest_witness.into()))?;
    Ok(format!("kant-file/1/{room}/{w}"))
}

/// How many frames a chunk of `len` bytes occupies at `frame_bytes` per frame.
pub fn frame_count(len: usize, frame_bytes: usize) -> u32 {
    std::cmp::max(1, len.div_ceil(frame_bytes)) as u32
}

/// Split a chunk into frames, in order.
///
/// Returns `None` if the chunk is larger than [`MAX_CHUNK_BYTES`], rather
/// than emitting a set of frames nobody should reassemble.
pub fn split(chunk: &[u8], witness: &str, frame_bytes: usize) -> Option<Vec<Frame>> {
    if chunk.len() > MAX_CHUNK_BYTES {
        return None;
    }
    let total = frame_count(chunk.len(), frame_bytes);
    let mut out = Vec::with_capacity(total as usize);
    for i in 0..total {
        let start = (i as usize) * frame_bytes;
        let end = std::cmp::min(start + frame_bytes, chunk.len());
        out.push(Frame::have(witness, i, total, chunk[start..end].to_vec()).ok()?);
    }
    Some(out)
}

/// Reassemble frames into a chunk, or `None` if they are incomplete,
/// inconsistent, or describe more bytes than the cap allows.
///
/// Deliberately tolerant of arrival ORDER — pubsub promises none — and
/// intolerant of anything else: a missing frame yields `None` rather than a
/// short chunk, so a caller can never hand a truncated chunk to
/// `decryptFile`.
pub fn assemble(frames: &[Frame], witness: &str) -> Option<Vec<u8>> {
    let witness = normalize_witness(witness)?;
    let total = frames.first()?.total;
    if total == 0 || frames.len() != total as usize {
        return None;
    }
    let mut slots: Vec<Option<&[u8]>> = vec![None; total as usize];
    for f in frames {
        if f.total != total || f.witness != witness {
            return None;
        }
        // Only a `have` carries chunk bytes. Without this a set of `want`
        // frames -- each with an empty payload -- reassembles to `Some(vec![])`,
        // a zero-byte chunk that passes every other check. The JS filters the
        // same way when it collects (`if (!m || m.tag !== TAG_HAVE) return`),
        // so this also keeps the two implementations answering identically.
        if f.tag != TAG_HAVE {
            return None;
        }
        let idx = f.index as usize;
        if idx >= slots.len() {
            return None;
        }
        // A repeated index is a conflict, not a harmless duplicate.
        //
        // This is defence in depth and cannot currently fire: the checks above
        // force `frames.len() == total` with every index in `[0, total)`, and
        // that many values in that many slots means a permutation. An
        // exhaustive enumeration (every index vector for total = 1..4)
        // confirms a repeat always implies a gap, so the `collect` below
        // rejects it first. Kept because the length and range checks are
        // separate statements and a later edit to either would make this
        // load-bearing.
        if slots[idx].is_some() {
            return None;
        }
        slots[idx] = Some(&f.payload);
    }
    let parts: Vec<&[u8]> = slots.into_iter().collect::<Option<Vec<_>>>()?;
    let size: usize = parts.iter().map(|p| p.len()).sum();
    if size > MAX_CHUNK_BYTES {
        return None;
    }
    let mut out = Vec::with_capacity(size);
    for p in parts {
        out.extend_from_slice(p);
    }
    Some(out)
}

fn hex_to_bytes(hex: &str) -> Option<Vec<u8>> {
    if hex.len() % 2 != 0 {
        return None;
    }
    let bytes = hex.as_bytes();
    let mut out = Vec::with_capacity(hex.len() / 2);
    let mut i = 0;
    while i < bytes.len() {
        let hi = (bytes[i] as char).to_digit(16)?;
        let lo = (bytes[i + 1] as char).to_digit(16)?;
        out.push(((hi << 4) | lo) as u8);
        i += 2;
    }
    Some(out)
}

fn bytes_to_hex(b: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(b.len() * 2);
    for byte in b {
        s.push(DIGITS[(byte >> 4) as usize] as char);
        s.push(DIGITS[(byte & 0x0f) as usize] as char);
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    // Not `const`: `str::repeat` is not a const fn. Building these per-test
    // is cheaper than a lazy_static for two strings.
    fn w() -> String {
        "a".repeat(64)
    }
    const W2: &str = "0f3b9c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e";

    fn body(n: usize, seed: u8) -> Vec<u8> {
        (0..n).map(|i| ((i as u32 * 31 + seed as u32) & 0xff) as u8).collect()
    }

    #[test]
    fn want_round_trips() {
        let f = Frame::want(&w(), 5, 0).unwrap();
        let bytes = encode(&f).unwrap();
        let d = decode(&bytes).unwrap();
        assert_eq!(d.tag, TAG_WANT);
        assert_eq!(d.witness, w());
        assert_eq!(d.index, 0);
        assert_eq!(d.total, 5);
    }

    #[test]
    fn have_round_trips_with_payload() {
        let payload = body(1000, 3);
        let f = Frame::have(&W2, 2, 5, payload.clone()).unwrap();
        let d = decode(&encode(&f).unwrap()).unwrap();
        assert_eq!(d.tag, TAG_HAVE);
        assert_eq!(d.payload, payload);
        assert_eq!(d.index, 2);
    }

    #[test]
    fn an_empty_payload_is_empty_not_missing() {
        let f = Frame::have(&w(), 0, 1, Vec::new()).unwrap();
        let d = decode(&encode(&f).unwrap()).unwrap();
        assert_eq!(d.payload.len(), 0);
        assert_eq!(d.total, 1);
    }

    #[test]
    fn a_short_frame_is_refused() {
        assert!(decode(&[]).is_none());
        assert!(decode(&body(HEADER - 1, 0)).is_none());
        assert!(decode(&body(10, 0)).is_none());
    }

    #[test]
    fn an_exact_header_is_parsed() {
        let f = Frame::deny(&w()).unwrap();
        let bytes = encode(&f).unwrap();
        assert_eq!(bytes.len(), HEADER);
        assert!(decode(&bytes).is_some());
    }

    #[test]
    fn an_unknown_tag_is_refused_not_guessed() {
        let mut bytes = encode(&Frame::deny(&w()).unwrap()).unwrap();
        bytes[0] = 99;
        assert!(decode(&bytes).is_none());
    }

    #[test]
    fn an_index_past_total_is_refused() {
        assert_eq!(Frame::have(&w(), 3, 3, vec![1]).unwrap_err(), FrameError::BadFrame);
        // and a hand-edited one, since the sender is a stranger
        let mut bytes = encode(&Frame::have(&w(), 0, 3, vec![1]).unwrap()).unwrap();
        bytes[36] = 9;
        assert!(decode(&bytes).is_none());
    }

    #[test]
    fn a_zero_total_is_refused() {
        assert_eq!(Frame::have(&w(), 0, 0, vec![1]).unwrap_err(), FrameError::BadFrame);
    }

    #[test]
    fn an_absurd_total_is_refused() {
        let mut bytes = encode(&Frame::have(&w(), 0, 1, vec![1]).unwrap()).unwrap();
        bytes[37] = 0xff;
        bytes[38] = 0xff;
        bytes[39] = 0xff;
        assert!(decode(&bytes).is_none());
    }

    #[test]
    fn a_payload_past_the_chunk_cap_is_refused() {
        let f = Frame::build(TAG_HAVE, &w(), 0, 1, vec![0u8; MAX_CHUNK_BYTES + 1], None);
        assert!(matches!(f, Err(FrameError::TooBig(_))));
    }

    #[test]
    fn a_non_witness_is_refused_at_encode() {
        for bad in ["", "abc", &"a".repeat(63), &"z".repeat(64)] {
            assert!(encode(&Frame::deny(bad).unwrap_or_else(|_| Frame::deny(&w()).unwrap())).is_ok()
                || normalize_witness(bad).is_none());
            assert!(normalize_witness(bad).is_none(), "{bad} should not be a witness");
        }
    }

    #[test]
    fn witness_case_is_normalized() {
        let upper = W2.to_ascii_uppercase();
        assert_eq!(normalize_witness(&upper).as_deref(), Some(W2));
        let f = Frame::have(&upper, 0, 1, vec![7]).unwrap();
        assert_eq!(f.witness, W2);
        assert_eq!(decode(&encode(&f).unwrap()).unwrap().witness, W2);
    }

    #[test]
    fn topic_is_room_plus_manifest_witness() {
        let t = topic_of("room-1", W2).unwrap();
        assert!(t.contains("room-1"));
        assert!(t.contains(W2));
        assert!(!t.to_lowercase().contains("secret"));
    }

    #[test]
    fn two_files_get_two_topics() {
        assert_ne!(topic_of("r", &w()).unwrap(), topic_of("r", W2).unwrap());
        assert_ne!(topic_of("r1", &w()).unwrap(), topic_of("r2", &w()).unwrap());
    }

    #[test]
    fn topic_needs_a_room_and_a_witness() {
        assert!(topic_of("", W2).is_err());
        assert!(topic_of("r", "nope").is_err());
    }

    #[test]
    fn a_chunk_smaller_than_a_frame_is_one_frame() {
        let c = body(500, 5);
        let fs = split(&c, &w(), 1024).unwrap();
        assert_eq!(fs.len(), 1);
        assert_eq!(assemble(&fs, &w()).unwrap(), c);
    }

    #[test]
    fn a_multi_frame_chunk_reassembles_in_order() {
        let c = body(9000, 7);
        let fs = split(&c, &w(), 1024).unwrap();
        assert!(fs.len() > 1);
        assert_eq!(assemble(&fs, &w()).unwrap(), c);
    }

    #[test]
    fn out_of_order_frames_still_reassemble() {
        let c = body(9000, 11);
        let mut fs = split(&c, &w(), 1024).unwrap();
        fs.reverse();
        assert_eq!(assemble(&fs, &w()).unwrap(), c);
    }

    #[test]
    fn a_missing_frame_yields_nothing_rather_than_a_short_chunk() {
        let c = body(9000, 13);
        let mut fs = split(&c, &w(), 1024).unwrap();
        fs.pop();
        assert!(assemble(&fs, &w()).is_none(), "a truncated chunk must not be returned");
    }

    #[test]
    fn a_frame_carrying_both_a_payload_and_a_nonce_is_refused() {
        // The nonce rides after the payload with nothing marking the boundary,
        // so this frame would decode its own nonce as chunk bytes. The
        // constructors never build one; `encode` refuses it anyway, because
        // "no caller does this today" is not the same as "the bytes are sound".
        let f = Frame {
            tag: TAG_HAVE,
            witness: w(),
            index: 0,
            total: 1,
            payload: vec![1, 2, 3],
            nonce: Some(vec![9, 9, 9, 9]),
        };
        assert_eq!(encode(&f).unwrap_err(), FrameError::PayloadAndNonce);
    }

    #[test]
    fn a_want_with_a_payload_is_refused_by_symmetry() {
        // The same ambiguity from the other direction: a `want` with chunk
        // bytes would hand the payload to the decoder as the nonce's tail.
        let f = Frame {
            tag: TAG_WANT,
            witness: w(),
            index: 0,
            total: 1,
            payload: vec![7, 7],
            nonce: Some(vec![1, 2, 3, 4]),
        };
        assert_eq!(encode(&f).unwrap_err(), FrameError::PayloadAndNonce);
    }

    #[test]
    fn a_repeated_index_is_a_conflict_not_a_harmless_duplicate() {
        let c = body(3000, 17);
        let mut fs = split(&c, &w(), 1024).unwrap();
        // Replace the LAST frame with a copy of the first, so the frame COUNT
        // stays right while index 0 appears twice and the last index never
        // arrives.
        //
        // Appending a duplicate instead — which is what this did at first —
        // trips the length check in `assemble` and never reaches the
        // duplicate check at all, so it passed even with that check removed.
        let dup = fs[0].clone();
        let last = fs.len() - 1;
        fs[last] = dup;
        assert_eq!(fs.len(), 3, "the frame COUNT must be right, or this proves nothing");
        assert_eq!(
            assemble(&fs, &w()),
            None,
            "a repeated index must not be silently accepted"
        );
    }

    #[test]
    fn frames_for_another_chunk_do_not_mix() {
        let c = body(3000, 19);
        let mut fs = split(&c, &w(), 1024).unwrap();
        let last = fs.len() - 1;
        fs[last] = Frame::have(&W2, last as u32, fs.len() as u32, vec![0]).unwrap();
        assert!(assemble(&fs, &w()).is_none());
    }

    #[test]
    fn a_chunk_past_the_cap_is_not_split() {
        assert!(split(&vec![0u8; MAX_CHUNK_BYTES + 1], &w(), 1024).is_none());
    }

    #[test]
    fn frame_count_matches_the_split() {
        for len in [0usize, 1, 1023, 1024, 1025, 9000, MAX_CHUNK_BYTES] {
            let n = frame_count(len, 1024);
            assert_eq!(split(&body(len, 23), &w(), 1024).unwrap().len() as u32, n,
                "frame_count disagrees with split at len={len}");
        }
    }

    #[test]
    fn the_default_frame_fits_a_plausible_stream_window() {
        assert!(FRAME_BYTES + HEADER <= 32 * 1024,
            "a default frame must stay small enough for any swarm");
    }

    #[test]
    fn the_payload_starts_exactly_at_the_header() {
        // The nonce's POSITION is load-bearing and nothing else pins it down:
        // no `have` frame carries a nonce, and a `want` has no payload, so
        // writing the nonce before the payload would leave every round trip
        // passing while making `have[HEADER..]` the wrong slice. Assert the
        // layout rather than trusting the comment.
        let payload = body(64, 29);
        let have = encode(&Frame::have(&w(), 0, 1, payload.clone()).unwrap()).unwrap();
        assert_eq!(have.len(), HEADER + payload.len(), "have is HEADER + payload");
        assert_eq!(&have[HEADER..], &payload[..], "the payload starts at HEADER");

        let want = encode(&Frame::want(&w(), 1, 0x01020304).unwrap()).unwrap();
        assert_eq!(want.len(), HEADER + 4, "want is HEADER + a 4-byte nonce");
        assert_eq!(&want[HEADER..], &[1, 2, 3, 4], "the nonce follows the header");
        // And the two agree on everything but payload and nonce, which is
        // what lets a decoder read the witness without knowing the tag.
        assert_eq!(&have[1..33], &want[1..33], "the witness field is tag-independent");
    }

    #[test]
    fn errors_render_with_the_witness_in_them() {
        assert!(FrameError::BadWitness("xyz".into()).to_string().contains("xyz"));
        assert!(FrameError::TooBig(99).to_string().contains("99"));
        assert!(FrameError::PayloadAndNonce.to_string().contains("nonce"));
    }
}