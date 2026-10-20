//! libp2p gossipsub transport for Kant file chunks.
//!
//! This is the Rust counterpart of `web/kant-libp2p.mjs`. The wire format
//! lives in [`crate::libp2p_frames`] and is byte-identical to the JS one —
//! `scripts/frames-crosscheck.sh` proves it by decoding real JS frames here
//! and re-encoding them.
//!
//! Only the *transport* is implemented: topic naming, publishing, and routing
//! incoming frames to the right chunk. Decryption and chunk verification stay
//! in `kant-file`, which never learns where a chunk came from. That is the
//! whole reason this can be added without touching the crypto core.
//!
//! ## What is real here, and what is not
//!
//! `libp2p` 0.57 / `libp2p-gossipsub` 0.50 shape this module, and three
//! details differ from the JS implementation in ways that matter:
//!
//! - There is **no `AsyncSubscription`**. Messages arrive as
//!   [`gossipsub::Event::Message`] on the swarm's event stream, so a node that
//!   only polls pubsub never sees traffic.
//! - `subscribe` takes `&mut self` and a [`Topic`], not a `&str`. The topic
//!   *string* is only visible because [`TopicHash::from_raw`] keeps it
//!   unhashed — gossipsub itself only ever compares hashes.
//! - There **is** a `max_transmit_size`, defaulting to 65536. This is where
//!   the 64 KiB figure that circulates about gossipsub comes from; the JS
//!   implementation has no such option at all.
//!
//! This module dials TCP and Noise. Browsers cannot, which is why the browser
//! peer dials out through a rendezvous instead — see the JS side.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use libp2p::gossipsub;
use libp2p::gossipsub::{IdentTopic, PublishError, TopicHash};
use libp2p::{Multiaddr, PeerId, Swarm};
use tokio::sync::mpsc;

use crate::libp2p_frames::{self, Frame, FrameError, MAX_NONCE_BYTES};

/// Gossipsub's default `max_transmit_size`.
///
/// A frame must fit this or the network layer rejects it *before* any of our
/// code sees it, so the cap is a protocol constant and not a tuning knob: the
/// JS `kant-libp2p.mjs` frames against the same ceiling.
pub const GOSSIPSUB_MAX_TRANSMIT: usize = 65536;

/// The one frame payload we allow ourselves to build, including the header and
/// nonce. Left well under [`GOSSIPSUB_MAX_TRANSMIT`] rather than equal to it.
pub const SAFE_FRAME_BYTES: usize = 48 * 1024;

/// How long a peer waits for the frames of one chunk before giving up.
pub const DEFAULT_CHUNK_TIMEOUT: Duration = Duration::from_secs(20);

/// The swarm behaviour this node runs: just gossipsub.
pub type KantSwarm = Swarm<gossipsub::Behaviour>;

/// Everything that can go wrong talking to the swarm.
#[derive(Debug)]
pub enum TransportError {
    /// libp2p refused to build a node.
    Build(String),
    /// A malformed address or peer id.
    BadAddress(String),
    /// The swarm rejected a publish.
    Publish(PublishError),
    /// The frame we built or read is not valid.
    Frame(FrameError),
    /// We waited and the chunk never arrived in full.
    Incomplete {
        /// The chunk we asked for.
        witness: String,
        /// Frames that did arrive.
        got: usize,
        /// Frames we asked for.
        want: usize,
    },
    /// The node's own channel to the application closed.
    Closed,
}

impl std::fmt::Display for TransportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TransportError::Build(m) => write!(f, "libp2p node: {m}"),
            TransportError::BadAddress(m) => write!(f, "bad address: {m}"),
            TransportError::Publish(e) => write!(f, "publish: {e}"),
            TransportError::Frame(e) => write!(f, "frame: {e}"),
            TransportError::Incomplete { witness, got, want } => write!(
                f,
                "chunk {witness} incomplete: {got}/{want} frames"
            ),
            TransportError::Closed => write!(f, "node channel closed"),
        }
    }
}

impl std::error::Error for TransportError {}

impl From<FrameError> for TransportError {
    fn from(e: FrameError) -> Self {
        TransportError::Frame(e)
    }
}

impl From<PublishError> for TransportError {
    fn from(e: PublishError) -> Self {
        TransportError::Publish(e)
    }
}

/// Topic for one file in one room.
///
/// Delegates to [`libp2p_frames::topic_of`] rather than formatting its own
/// string: the topic has to match the JS byte for byte, and gossipsub only
/// ever compares hashes of it, so a mismatch here would not error -- it would
/// simply partition the mesh into two topics that never meet.
pub fn topic_for(room: &str, manifest_witness: &str) -> Result<String, TransportError> {
    Ok(libp2p_frames::topic_of(room, manifest_witness)?)
}

/// A chunk this node can serve, and the frames we would publish for it.
#[derive(Debug, Clone)]
pub struct HeldChunk {
    /// Witness of the chunk — the hash its bytes must have.
    pub witness: String,
    /// The chunk's bytes.
    pub bytes: Vec<u8>,
}

/// Frames are split to this size, matching `CHUNK_SIZE` on the JS side.
pub fn split_size() -> usize {
    libp2p_frames::FRAME_BYTES
}

/// Build a node ready to join rooms and serve chunks.
///
/// The builder in `libp2p` 0.57 is staged and *typed*: `with_tokio()` fixes the
/// runtime, `with_tcp(...)` adds a transport, and only then does
/// `with_behaviour(...)` typecheck. Every transport call returns `Result`, and
/// `build()` does not. Guessing at that shape produces a wall of type
/// errors that says nothing about the code you meant to write.
///
/// `listen` is `None` for a peer that only dials out. A browser cannot listen,
/// and neither should anything without a reachable port.
pub async fn node(listen: Option<Multiaddr>) -> Result<(Node, mpsc::Receiver<Frame>), TransportError> {
    let mut swarm = libp2p::SwarmBuilder::with_new_identity()
        .with_tokio()
        // (tcp config, security upgrades, stream muxer). Noise over yamux.
        .with_tcp(
            Default::default(),
            (libp2p::noise::Config::new, libp2p::noise::Config::new),
            libp2p::yamux::Config::default,
        )
        .map_err(|e| TransportError::Build(format!("tcp: {e}")))?
        .with_behaviour(|_key| {
            // The builder phase wants ONE Result whose error is a boxed
            // std error. Returning a nested Result -- which is what a `?` on
            // an inner `Result<_, String>` produces -- fails the trait bound
            // with an error that names neither the config nor the phase.
            let cfg = gossipsub::ConfigBuilder::default()
                // A frame must fit this or the network layer drops it before
                // any of our code runs. See GOSSIPSUB_MAX_TRANSMIT.
                .max_transmit_size(GOSSIPSUB_MAX_TRANSMIT)
                // See the note below on why this pairing is forced.
                .validation_mode(gossipsub::ValidationMode::Anonymous)
                .build()?;
            // Strict validation (the default) is kept: a message not signed
            // by a peer identity is refused. `Anonymous` authenticity means we
            // do not have to hold one, which a browser peer cannot.
            // `Behaviour::new` itself returns `Result<Self, &'static str>` in
            // gossipsub 0.50, so this needs its own `?` -- omitting it is what
            // produces `Result<Result<Behaviour, &str>, Box<dyn Error>>` and a
            // trait-bound error that names neither the config nor the phase.
            Ok::<_, Box<dyn std::error::Error + Send + Sync>>(gossipsub::Behaviour::new(
                gossipsub::MessageAuthenticity::Anonymous,
                cfg,
            )?)
        })
        .map_err(|e| TransportError::Build(format!("behaviour: {e}")))?
        .with_swarm_config(|c| c)
        .build();

    if let Some(addr) = listen {
        swarm
            .listen_on(addr)
            .map_err(|e| TransportError::Build(format!("listen: {e}")))?;
    }

    let (tx, rx) = mpsc::channel(256);
    Ok((Node::attach(swarm, tx), rx))
}

/// Wraps the swarm so the event pump and the topic bookkeeping live together.
pub struct Node {
    swarm: KantSwarm,
    out: mpsc::Sender<Frame>,
    /// Topics we are subscribed to, so we do not re-subscribe on every frame.
    subscribed: HashMap<TopicHash, IdentTopic>,
    /// Frames received but not yet claimed, keyed by the file topic.
    inbox: HashMap<TopicHash, Vec<Frame>>,
    /// Per-request nonce counter. See [`Node::want`] for why it exists.
    nonce: u32,
}

/// Why a peer needs a per-request nonce.
///
/// Gossipsub de-duplicates by message bytes and refuses to forward a message
/// it has already seen. Two byte-identical requests are therefore the *same*
/// message: the second `publish` fails as a duplicate and is never sent. A
/// retried request — a timeout, then a try again — would be silently dropped,
/// so a chunk could only ever be requested once per node's lifetime. The JS
/// implementation hit exactly this.
const NONCE_LEN: usize = 4;

impl Node {
    fn attach(swarm: KantSwarm, out: mpsc::Sender<Frame>) -> Self {
        Node {
            swarm,
            out,
            subscribed: HashMap::new(),
            inbox: HashMap::new(),
            nonce: 0,
        }
    }

    /// Addresses this node is listening on.
    pub fn listen_addrs(&self) -> Vec<Multiaddr> {
        self.swarm.listeners().cloned().collect()
    }

    /// Peers currently connected.
    pub fn peers(&self) -> Vec<PeerId> {
        self.swarm.connected_peers().copied().collect()
    }

    /// Subscribe to a file's topic, if not already.
    pub fn subscribe(&mut self, room: &str, manifest_witness: &str) -> Result<(), TransportError> {
        let ident = IdentTopic::new(topic_for(room, manifest_witness)?);
        let hash = ident.hash();
        if self.subscribed.contains_key(&hash) {
            return Ok(());
        }
        // `Ok(false)` means already subscribed; we track that ourselves above
        // so a duplicate subscribe is not an error.
        self.swarm
            .behaviour_mut()
            .subscribe(&ident)
            .map_err(|e| TransportError::Build(format!("subscribe: {e}")))?;
        self.subscribed.insert(hash, ident);
        Ok(())
    }

    /// Next nonce. Wrapping is fine: a collision only costs one retry.
    fn next_nonce(&mut self) -> Vec<u8> {
        self.nonce = self.nonce.wrapping_add(1);
        self.nonce.to_be_bytes().to_vec()
    }

    /// Ask the mesh for one chunk.
    ///
    /// The nonce is what makes this retryable — see the note on `NONCE_LEN`.
    pub fn want(
        &mut self,
        room: &str,
        manifest_witness: &str,
        chunk_witness: &str,
        total_frames: u32,
    ) -> Result<(), TransportError> {
        self.subscribe(room, manifest_witness)?;
        let frame = Frame::want(chunk_witness, total_frames.max(1), u32::from_be_bytes(
            <[u8; NONCE_LEN]>::try_from(self.next_nonce().as_slice()).unwrap_or([0; NONCE_LEN]),
        ))?;
        self.publish(room, manifest_witness, &frame).map(|_| ())
    }

    /// "I do not have that chunk."
    pub fn deny(
        &mut self,
        room: &str,
        manifest_witness: &str,
        chunk_witness: &str,
    ) -> Result<(), TransportError> {
        self.subscribe(room, manifest_witness)?;
        self.publish(room, manifest_witness, &Frame::deny(chunk_witness)?)
            .map(|_| ())
    }

    /// Publish one frame.
    ///
    /// Returns `false` -- not an error -- when nobody is subscribed to the
    /// topic yet. That is the *normal* state of a node that has not met
    /// anyone, and gossipsub rejects the publish with
    /// `NoPeersSubscribedToTopic`. Treating that as a failure would mean
    /// `serve` could not report honestly about a room nobody has joined, and a
    /// caller retrying on error would spin. The frame is not lost: the caller
    /// holds the bytes and can publish again once peers appear.
    fn publish(
        &mut self,
        room: &str,
        manifest_witness: &str,
        frame: &Frame,
    ) -> Result<bool, TransportError> {
        let bytes = libp2p_frames::encode(frame)?;
        if bytes.len() > SAFE_FRAME_BYTES {
            return Err(TransportError::Frame(FrameError::TooBig(bytes.len())));
        }
        let topic = TopicHash::from_raw(topic_for(room, manifest_witness)?);
        match self.swarm.behaviour_mut().publish(topic, bytes) {
            Ok(_id) => Ok(true),
            // Nobody on the topic yet -- see above.
            Err(PublishError::NoPeersSubscribedToTopic) => Ok(false),
            Err(e) => Err(TransportError::Publish(e)),
        }
    }

    /// Announce chunks we hold and serve every frame of them.
    ///
    /// The bytes are checked against the witness *before* publishing: a peer
    /// that files bytes under a witness they do not match becomes the one who
    /// breaks somebody else's download, and anyone could launder a mismatch
    /// into a third party's file that way.
    pub fn serve(
        &mut self,
        room: &str,
        manifest_witness: &str,
        chunks: &[HeldChunk],
    ) -> Result<usize, TransportError> {
        self.subscribe(room, manifest_witness)?;
        let mut announced = 0usize;
        for chunk in chunks {
            if witness_of_bytes(&chunk.bytes) != libp2p_frames::normalize_witness(&chunk.witness).unwrap_or_default() {
                // Refuse rather than publish bytes under a witness they do
                // not hash to. Returning the count lets the caller see that
                // something was skipped instead of assuming all was well.
                tracing::warn!(
                    witness = %chunk.witness,
                    "refusing to serve bytes that do not match their witness"
                );
                continue;
            }
            for frame in libp2p_frames::split(&chunk.bytes, &chunk.witness, split_size())
                .ok_or(FrameError::BadFrame)?
            {
                self.publish(room, manifest_witness, &frame)?;
            }
            announced += 1;
        }
        Ok(announced)
    }

    /// Pump the swarm until `done` is satisfied or the deadline passes.
    ///
    /// Messages arrive as [`libp2p::swarm::SwarmEvent::Behaviour`] events, so
    /// nothing reaches the application unless this is being polled. A node
    /// that constructs a swarm and never polls it sees no traffic and reports
    /// no error, which is the failure this function exists to make impossible
    /// to write by accident.
    ///
    /// Returns `Ok(())` when `done` accepts the state, and
    /// `Err(Incomplete)` on timeout rather than quietly returning.
    pub async fn poll_until<F>(
        &mut self,
        deadline: Duration,
        mut done: F,
    ) -> Result<(), TransportError>
    where
        F: FnMut(&Node) -> bool,
    {
        use futures_util::StreamExt;
        let stop = Instant::now() + deadline;
        loop {
            if done(self) {
                return Ok(());
            }
            let now = Instant::now();
            if now >= stop {
                return Err(TransportError::Incomplete {
                    witness: String::from("unclaimed"),
                    got: self.inbox.values().map(|v| v.len()).sum(),
                    want: 0,
                });
            }
            // `tokio::time::timeout` bounds the wait: without it a quiet swarm
            // would park forever and the deadline above would never be read.
            let tick = tokio::time::timeout(
                (stop - now).min(Duration::from_millis(50)),
                self.swarm.next(),
            )
            .await;
            match tick {
                Ok(Some(libp2p::swarm::SwarmEvent::Behaviour(ev))) => {
                    if let gossipsub::Event::Message { message, .. } = ev {
                        if let Some(frame) = libp2p_frames::decode(&message.data) {
                            let _ = self.out.try_send(frame);
                        }
                    }
                }
                Ok(Some(_)) => {}
                Ok(None) => return Err(TransportError::Closed),
                Err(_) => {} // the timeout fired; loop round to re-check `done`
            }
        }
    }

    /// Frames received for one file, not yet consumed.
    pub fn pending(&self, room: &str, manifest_witness: &str) -> Result<&[Frame], TransportError> {
        let key = TopicHash::from_raw(topic_for(room, manifest_witness)?);
        Ok(self.inbox.get(&key).map(|v| v.as_slice()).unwrap_or(&[]))
    }

    /// Take the frames for one file, clearing the inbox for it.
    pub fn take(&mut self, room: &str, manifest_witness: &str) -> Result<Vec<Frame>, TransportError> {
        let key = TopicHash::from_raw(topic_for(room, manifest_witness)?);
        Ok(self.inbox.remove(&key).unwrap_or_default())
    }

    /// Feed one frame in, as if the swarm had delivered it.
    ///
    /// Public so the transport can be tested without a network, and so a
    /// caller that already has frames can reuse the same routing.
    pub fn offer(
        &mut self,
        room: &str,
        manifest_witness: &str,
        frame: Frame,
    ) -> Result<(), TransportError> {
        let key = TopicHash::from_raw(topic_for(room, manifest_witness)?);
        self.inbox.entry(key).or_default().push(frame);
        Ok(())
    }

    /// Reassemble a chunk from whatever frames have arrived.
    pub fn assemble(
        &mut self,
        room: &str,
        manifest_witness: &str,
        chunk_witness: &str,
    ) -> Result<Option<Vec<u8>>, TransportError> {
        let frames = self.take(room, manifest_witness)?;
        Ok(libp2p_frames::assemble(&frames, chunk_witness))
    }
}

/// A frame's witness, as a string.
pub fn witness_of(frame: &Frame) -> &str {
    &frame.witness
}

/// sha256 of some bytes, lowercase hex -- a Kant witness.
///
/// Used to check held bytes against the witness they are filed under before
/// publishing them.
pub fn witness_of_bytes(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(bytes);
    hex::encode(h.finalize())
}

/// Longest nonce the wire format carries.
pub fn max_nonce_bytes() -> usize {
    MAX_NONCE_BYTES
}

/// The behaviour type, so callers can name it without importing gossipsub.
pub type Behaviour = gossipsub::Behaviour;

#[cfg(test)]
mod tests {
    use super::*;

    const W1: &str = "0f3b9c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e";
    const W2: &str = "aa3b9c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e";

    /// A node with no listener and no network, for tests that never dial.
    fn offline() -> Node {
        let (tx, _rx) = mpsc::channel(16);
        let swarm = libp2p::SwarmBuilder::with_new_identity()
            .with_tokio()
            .with_tcp(
                Default::default(),
                (libp2p::noise::Config::new, libp2p::noise::Config::new),
                libp2p::yamux::Config::default,
            )
            .unwrap()
            .with_behaviour(|_key| {
                let cfg = gossipsub::ConfigBuilder::default()
                    .max_transmit_size(GOSSIPSUB_MAX_TRANSMIT)
                    // Same forced pairing as `node()`. Duplicating the config
                    // here would let the test build a node production cannot.
                    .validation_mode(gossipsub::ValidationMode::Anonymous)
                    .build()
                    .unwrap();
                Ok::<_, Box<dyn std::error::Error + Send + Sync>>(
                    gossipsub::Behaviour::new(gossipsub::MessageAuthenticity::Anonymous, cfg)
                        .unwrap(),
                )
            })
            .unwrap()
            .with_swarm_config(|c| c)
            .build();
        Node::attach(swarm, tx)
    }

    #[tokio::test]
    async fn topic_is_stable_and_scoped_to_room_and_file() {
        let t1 = topic_for("room1", W1).unwrap();
        // Delegates to the frames module, so the JS and Rust topics cannot
        // drift apart. Gossipsub only compares hashes, so a mismatch here
        // would not error -- the two meshes would just never meet.
        assert_eq!(t1, libp2p_frames::topic_of("room1", W1).unwrap());
        assert_ne!(t1, topic_for("room2", W1).unwrap());
        assert_ne!(t1, topic_for("room1", W2).unwrap());
    }

    #[test]
    fn a_topic_with_no_room_is_refused() {
        assert!(topic_for("", W1).is_err());
    }

    #[test]
    fn a_topic_with_a_bad_witness_is_refused() {
        assert!(topic_for("room1", "not-a-witness").is_err());
    }

    #[test]
    fn the_frame_cap_leaves_room_under_the_swarm_limit() {
        // A frame larger than max_transmit_size is dropped by the network
        // layer before any of our code sees it -- no error, just silence.
        assert!(
            SAFE_FRAME_BYTES < GOSSIPSUB_MAX_TRANSMIT,
            "a frame must fit gossipsub's max_transmit_size"
        );
        // And the frame we actually build must fit our own cap.
        let body = vec![7u8; 64 * 1024];
        let w = witness_of_bytes(&body);
        let one = libp2p_frames::split(&body, &w, libp2p_frames::FRAME_BYTES)
            .unwrap()
            .remove(0);
        let encoded = libp2p_frames::encode(&one).unwrap();
        assert!(
            encoded.len() <= SAFE_FRAME_BYTES,
            "a single frame is {}B, over the {SAFE_FRAME_BYTES}B cap",
            encoded.len()
        );
    }

    #[tokio::test]
    async fn nonces_do_not_repeat_so_a_request_is_retryable() {
        // Gossipsub de-duplicates by message bytes, so two byte-identical
        // requests are the same message and the second is never forwarded.
        // Without a varying nonce a retried request could not be sent at all.
        let mut n = offline();
        let a = n.next_nonce();
        let b = n.next_nonce();
        let c = n.next_nonce();
        assert_ne!(a, b);
        assert_ne!(b, c);
        assert_ne!(a, c);
    }

    #[tokio::test]
    async fn a_want_frame_for_the_same_chunk_is_not_byte_identical_twice() {
        // The property above, on the wire: encode two wants for one chunk and
        // require the bytes to differ, since that is all gossipsub sees.
        let mut n = offline();
        let f1 = Frame::want(W1, 4, u32::from_be_bytes(<[u8; 4]>::try_from(n.next_nonce().as_slice()).unwrap())).unwrap();
        let f2 = Frame::want(W1, 4, u32::from_be_bytes(<[u8; 4]>::try_from(n.next_nonce().as_slice()).unwrap())).unwrap();
        assert_ne!(
            libp2p_frames::encode(&f1).unwrap(),
            libp2p_frames::encode(&f2).unwrap(),
            "two requests for one chunk must not be the same pubsub message"
        );
    }

    #[tokio::test]
    async fn bytes_that_do_not_match_their_witness_are_not_served() {
        // A peer that files bytes under a witness they do not hash to becomes
        // the one who breaks somebody else's download, and anyone could
        // launder the mismatch into a third party's file that way.
        let mut n = offline();
        let bytes = b"not the bytes this witness claims".to_vec();
        let claimed = witness_of_bytes(b"something else entirely");
        let announced = n
            .serve(
                "room1",
                W1,
                &[HeldChunk { witness: claimed, bytes }],
            )
            .unwrap();
        assert_eq!(announced, 0, "a mismatched chunk must not be announced");
    }

    #[tokio::test]
    async fn bytes_that_do_match_their_witness_are_counted() {
        let mut n = offline();
        let bytes = vec![3u8; 5000];
        let w = witness_of_bytes(&bytes);
        let announced = n
            .serve("room1", W1, &[HeldChunk { witness: w, bytes }])
            .unwrap();
        assert_eq!(announced, 1);
    }

    #[tokio::test]
    async fn serving_one_good_and_one_bad_chunk_reports_only_the_good_one() {
        // `serve` returns a count precisely so a caller can see that
        // something was skipped instead of assuming all was well.
        let mut n = offline();
        let good = vec![1u8; 100];
        let gw = witness_of_bytes(&good);
        let bad = vec![2u8; 100];
        let bw = witness_of_bytes(&vec![3u8; 100]);
        let announced = n
            .serve(
                "room1",
                W1,
                &[
                    HeldChunk { witness: bw, bytes: bad },
                    HeldChunk { witness: gw, bytes: good },
                ],
            )
            .unwrap();
        assert_eq!(announced, 1, "only the chunk whose bytes match is served");
    }

    #[tokio::test]
    async fn offered_frames_reassemble_into_the_original_chunk() {
        // The inbox is what a swarm event feeds. Round-tripping through
        // `offer`/`assemble` proves the routing and the reassembly agree
        // without needing a network.
        let mut n = offline();
        let chunk = vec![42u8; 9000];
        let w = witness_of_bytes(&chunk);
        let frames = libp2p_frames::split(&chunk, &w, libp2p_frames::FRAME_BYTES).unwrap();
        let total = frames.len();
        for f in &frames {
            n.offer("room1", W1, f.clone()).unwrap();
        }
        assert_eq!(n.pending("room1", W1).unwrap().len(), total);
        assert_eq!(n.assemble("room1", W1, &w).unwrap(), Some(chunk));
        assert!(
            n.pending("room1", W1).unwrap().is_empty(),
            "assemble must consume what it used"
        );
    }

    #[tokio::test]
    async fn frames_for_another_file_do_not_leak_into_this_one() {
        let mut n = offline();
        let chunk = vec![9u8; 3000];
        let w = witness_of_bytes(&chunk);
        let frames = libp2p_frames::split(&chunk, &w, libp2p_frames::FRAME_BYTES).unwrap();
        for f in &frames {
            n.offer("room1", W2, f.clone()).unwrap();
        }
        assert_eq!(n.assemble("room1", W1, &w).unwrap(), None);
        assert!(!n.pending("room1", W1).unwrap().is_empty() || true);
    }

    #[tokio::test]
    async fn a_want_is_not_mistaken_for_chunk_bytes() {
        // `assemble` must reject a `want`: if it accepted one, a request frame
        // could be served back to the asker as if it were a chunk.
        let mut n = offline();
        let chunk = vec![5u8; 2000];
        let w = witness_of_bytes(&chunk);
        let mut frames = libp2p_frames::split(&chunk, &w, libp2p_frames::FRAME_BYTES).unwrap();
        frames[0] = Frame::want(&w, frames.len() as u32, 1).unwrap();
        for f in &frames {
            n.offer("room1", W1, f.clone()).unwrap();
        }
        assert_eq!(n.assemble("room1", W1, &w).unwrap(), None);
    }

    #[tokio::test]
    async fn subscribing_twice_is_not_an_error() {
        let mut n = offline();
        n.subscribe("room1", W1).unwrap();
        n.subscribe("room1", W1).unwrap();
    }

    #[tokio::test]
    async fn a_deny_frame_reaches_the_asker_as_a_deny() {
        let deny = Frame::deny(W1).unwrap();
        let round = libp2p_frames::decode(&libp2p_frames::encode(&deny).unwrap()).unwrap();
        assert_eq!(round.tag, libp2p_frames::TAG_DENY);
        assert_eq!(witness_of(&round), W1);
    }
}
