// sheaf.rs — M→H→E mapping: Monster object M, subgroup H selects encoding, data E
// Each paste is a sheaf section with full DASL type classification.
// Types 0-7 from the 0xDA51 prefix taxonomy.
use crate::dasl;

const DA51: u64 = 0xDA51;

/// DASL address types (4-bit field, bits 47-44)
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DaslType {
    MonsterWalk = 0,  // 10-block Monster Walk with Bott periodicity
    AstNode = 1,      // AST node with bott×tenfold×hecke triple view
    Protocol = 2,     // Protocol negotiation and capability exchange
    NestedCid = 3,    // Content-addressed data with Monster structure
    HarmonicPath = 4, // Routing between 10-fold and 8-fold ways
    ShardId = 5,      // Distributed storage sharding
    Eigenspace = 6,   // Cl(15,0,0) eigenspace-aware addressing
    Hauptmodul = 7,   // Genus-0 modular function reference
}

/// Cl(15,0,0) eigenspaces
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum EigenSpace {
    Earth = 0,  // eigenvalue −1, primes {2,3,5,7,11,13,47}, 99.9996% energy
    Spoke = 1,  // eigenvalue −1, mixed from {17,29,31,41,59,71}
    Hub = 2,    // eigenvalue +1, direction (e₁₉+e₂₃)/√2
    Clock = 3,  // eigenvalue e^{±iπ/3}, 60° rotation plane
}

impl EigenSpace {
    pub fn name(&self) -> &'static str {
        match self { Self::Earth => "Earth", Self::Spoke => "Spoke", Self::Hub => "Hub", Self::Clock => "Clock" }
    }
}

/// Encoding types map to Monster supersingular primes
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Encoding {
    Raw,      // identity — no transform
    Base64,   // p=2 — simple, reversible
    Morse,    // p=3 — human-readable (skeleton prime)
    Split,    // p=5 — chunking for LLM
    Qr,       // p=7 — visual
    Dtmf,     // p=11 — audio
    Numbers,  // p=13 — voice
    Stego,    // p=47 — hidden in image (attack triple, Earth anomaly)
    Ipfs,     // p=59 — content-addressed (attack triple)
    Dasl,     // p=71 — full orbifold (attack triple)
}

impl Encoding {
    /// The Monster prime associated with this encoding's resolution level
    pub fn prime(&self) -> u64 {
        match self {
            Self::Raw => 1,
            Self::Base64 => 2,
            Self::Morse => 3,
            Self::Split => 5,
            Self::Qr => 7,
            Self::Dtmf => 11,
            Self::Numbers => 13,
            Self::Stego => 47,
            Self::Ipfs => 59,
            Self::Dasl => 71,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Raw => "raw", Self::Base64 => "base64", Self::Morse => "morse",
            Self::Split => "split", Self::Qr => "qr", Self::Dtmf => "dtmf",
            Self::Numbers => "numbers", Self::Stego => "stego",
            Self::Ipfs => "ipfs", Self::Dasl => "dasl",
        }
    }

    pub fn from_name(s: &str) -> Self {
        match s {
            "base64" => Self::Base64, "morse" => Self::Morse, "split" => Self::Split,
            "qr" => Self::Qr, "dtmf" => Self::Dtmf, "numbers" => Self::Numbers,
            "stego" => Self::Stego, "ipfs" => Self::Ipfs, "dasl" => Self::Dasl,
            _ => Self::Raw,
        }
    }
}

/// A sheaf section: the triple (M-shard, H-encoding, E-data) with DASL type
#[derive(Debug, Clone)]
pub struct Section {
    pub shard: (u64, u64, u64),   // orbifold coords (l mod 71, m mod 59, n mod 47)
    pub encoding: Encoding,        // subgroup H
    pub cid: String,               // content address of E
    pub dasl_cid: u64,             // DASL CID with Monster coords
    pub dasl_type: DaslType,       // 0xDA51 type field
    pub eigenspace: EigenSpace,    // Cl(15,0,0) eigenspace
    pub bott: u8,                  // Bott periodicity index (0-7)
    pub hecke: u8,                 // Hecke operator index (0-14)
}

impl Section {
    pub fn new(data: &[u8], encoding: Encoding) -> Self {
        let coords = dasl::orbifold_coords(data);
        let dasl_cid = dasl::nested_cid(data);
        let cid = format!("bafk{:x}", dasl_cid);
        let p = encoding.prime();
        // Classify eigenspace by prime
        let eigenspace = match p {
            2 | 3 | 5 | 7 | 11 | 13 | 47 => EigenSpace::Earth,
            17 | 29 | 31 | 41 | 59 | 71 => EigenSpace::Spoke,
            19 => EigenSpace::Hub,
            23 => EigenSpace::Clock,
            _ => EigenSpace::Earth,
        };
        // Bott index from data hash
        let bott = (coords.0 % 8) as u8;
        // Hecke index from prime
        let hecke = dasl::MONSTER_PRIMES.iter().position(|&mp| mp == p).unwrap_or(0) as u8;
        // Type: content gets NestedCid, protocols get Protocol, etc.
        let dasl_type = DaslType::NestedCid;
        Section { shard: coords, encoding, cid, dasl_cid, dasl_type, eigenspace, bott, hecke }
    }

    /// Full DASL address: [DA51:16][type:4][eigenspace:2][prime_idx:4][bott:3][hecke:4][hash:31]
    pub fn dasl_addr(&self) -> u64 {
        let hash = self.dasl_cid & 0x7FFFFFFF; // 31 bits
        (DA51 << 48)
            | ((self.dasl_type as u64) << 44)
            | ((self.eigenspace as u64) << 42)
            | ((self.hecke as u64) << 38)
            | ((self.bott as u64) << 35)
            | hash
    }

    /// Escaped RDFa with full DASL type info
    pub fn to_rdfa(&self) -> String {
        let (l, m, n) = self.shard;
        let enc = self.encoding.name();
        let p = self.encoding.prime();
        let addr = self.dasl_addr();
        [
            format!("&lt;div typeof=\"erdfa:SheafSection dasl:Type{}\" about=\"#{}\"&gt;",
                self.dasl_type as u8, self.cid),
            format!("  &lt;meta property=\"erdfa:shard\" content=\"{},{},{}\" /&gt;", l, m, n),
            format!("  &lt;meta property=\"erdfa:encoding\" content=\"{}\" /&gt;", enc),
            format!("  &lt;meta property=\"erdfa:prime\" content=\"{}\" /&gt;", p),
            format!("  &lt;meta property=\"dasl:addr\" content=\"0x{:016x}\" /&gt;", addr),
            format!("  &lt;meta property=\"dasl:type\" content=\"{}\" /&gt;", self.dasl_type as u8),
            format!("  &lt;meta property=\"dasl:eigenspace\" content=\"{}\" /&gt;", self.eigenspace.name()),
            format!("  &lt;meta property=\"dasl:bott\" content=\"{} ({})\" /&gt;", self.bott, dasl::BOTT_NAMES[self.bott as usize]),
            format!("  &lt;meta property=\"dasl:hecke\" content=\"T_{}\" /&gt;", p),
            format!("  &lt;meta property=\"sheaf:orbifold\" content=\"({} mod 71, {} mod 59, {} mod 47)\" /&gt;", l, m, n),
            format!("  &lt;link property=\"sheaf:subgroupIndex\" href=\"erdfa:H/{}\" /&gt;", enc),
            "&lt;/div&gt;".to_string(),
        ].join("\n")
    }

    /// Machine-readable RDFa (unescaped)
    pub fn to_rdfa_live(&self) -> String {
        let (l, m, n) = self.shard;
        let enc = self.encoding.name();
        let p = self.encoding.prime();
        let addr = self.dasl_addr();
        [
            format!("<div typeof=\"erdfa:SheafSection dasl:Type{}\" about=\"#{}\">",
                self.dasl_type as u8, self.cid),
            format!("  <meta property=\"erdfa:shard\" content=\"{},{},{}\" />", l, m, n),
            format!("  <meta property=\"erdfa:encoding\" content=\"{}\" />", enc),
            format!("  <meta property=\"erdfa:prime\" content=\"{}\" />", p),
            format!("  <meta property=\"dasl:addr\" content=\"0x{:016x}\" />", addr),
            format!("  <meta property=\"dasl:type\" content=\"{}\" />", self.dasl_type as u8),
            format!("  <meta property=\"dasl:eigenspace\" content=\"{}\" />", self.eigenspace.name()),
            format!("  <meta property=\"dasl:bott\" content=\"{} ({})\" />", self.bott, dasl::BOTT_NAMES[self.bott as usize]),
            format!("  <meta property=\"dasl:hecke\" content=\"T_{}\" />", p),
            format!("  <meta property=\"sheaf:orbifold\" content=\"({} mod 71, {} mod 59, {} mod 47)\" />", l, m, n),
            format!("  <link property=\"sheaf:subgroupIndex\" href=\"erdfa:H/{}\" />", enc),
            "</div>".to_string(),
        ].join("\n")
    }
}

/// Restriction map: how data flows between two sections
pub fn restriction_map(source: &Section, target: &Section) -> String {
    [
        "&lt;div typeof=\"sheaf:RestrictionMap\"&gt;".to_string(),
        format!("  &lt;link property=\"sheaf:source\" href=\"#{}\" /&gt;", source.cid),
        format!("  &lt;link property=\"sheaf:target\" href=\"#{}\" /&gt;", target.cid),
        format!("  &lt;meta property=\"sheaf:coboundary\" content=\"δ: H/{} → H/{}\" /&gt;", source.encoding.name(), target.encoding.name()),
        format!("  &lt;meta property=\"sheaf:primeRatio\" content=\"{}/{}\" /&gt;", source.encoding.prime(), target.encoding.prime()),
        format!("  &lt;meta property=\"dasl:eigenflow\" content=\"{} → {}\" /&gt;", source.eigenspace.name(), target.eigenspace.name()),
        "&lt;/div&gt;".to_string(),
    ].join("\n")
}

/// Sheaf header line for paste metadata
pub fn sheaf_header(s: &Section) -> String {
    format!("Sheaf: {},{},{} H/{} p={} T{} {} B{} T_{}",
        s.shard.0, s.shard.1, s.shard.2,
        s.encoding.name(), s.encoding.prime(),
        s.dasl_type as u8, s.eigenspace.name(),
        s.bott, s.encoding.prime())
}
