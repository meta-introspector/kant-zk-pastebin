# ideacloud.nix — Declarative idea atoms with fingerprints and dependency ordering
#
# Each "idea" is a semantic node describing a detectable pattern in the codebase.
# The fingerprint tells apply.nix how to match source files to this idea.
# The deps field enables topological sorting so foundational patterns resolve first.

let
  ideas = [
    # ── Foundational: detect git submodules ──────────────────────────────
    {
      id = "git.submodule";
      pattern = "git submodule — a pointer to another git repository";
      fingerprint = {
        grep = "[submodule";
        lang = "git";
        filetype = ".gitmodules";
        tags = [ "submodule" "git" "pointer" ];
      };
      deps = [ ];
      emit = "symlink";
    }

    # ── Foundational: detect Cargo workspace members ─────────────────────
    {
      id = "workspace.member";
      pattern = "Cargo workspace member — a crate in the workspace";
      fingerprint = {
        grep = "plugins/";
        lang = "toml";
        filetype = "Cargo.toml";
        tags = [ "workspace" "crate" "member" ];
      };
      deps = [ "git.submodule" ];
      emit = "crate-ref";
    }

    # ── Foundational: detect Rust path dependencies ──────────────────────
    {
      id = "rust.path-dep";
      pattern = "Rust path dependency — a crate referenced by relative path";
      fingerprint = {
        grep = ".path = ";
        grep = "path = ";
        lang = "toml";
        filetype = "Cargo.toml";
        tags = [ "rust" "dependency" "path" ];
      };
      deps = [ "workspace.member" ];
      emit = "crate-ref";
    }

    # ── Intermediate: detect standalone buildable crates ─────────────────
    {
      id = "crate.standalone";
      pattern = "Standalone crate — has its own Cargo.toml and can be built independently";
        grep = "buildRustPackage";
        lang = "nix";
        filetype = "flake.nix";
        tags = [ "nix" "package" "build" ];
      };
      deps = [ "workspace.member" "git.submodule" ];
      emit = "flake-input";
    }

    # ── Intermediate: detect standalone buildable crates ─────────────────
    {
      id = "crate.standalone";
      pattern = "Standalone crate — has its own Cargo.toml and can be built independently";
      fingerprint = {
        grep = "[package]";
        lang = "toml";
        filetype = "Cargo.toml";
        tags = [ "crate" "standalone" "buildable" ];
      };
      deps = [ "workspace.member" ];
      emit = "crate-build";
    }

    # ── Advanced: detect nested submodule chains ─────────────────────────
    {
      id = "submodule.nested";
      pattern = "Nested submodule — a .gitmodules within a submodule directory";
      fingerprint = {
        grep = "[submodule";
        lang = "git";
        filetype = ".gitmodules";
        tags = [ "submodule" "nested" "chain" ];
      };
      deps = [ "git.submodule" ];
      emit = "symlink";
    }

    # ── Advanced: detect CBOR/DAG-CBOR code patterns ────────────────────
    {
      id = "codec.cbor";
      pattern = "CBOR/DAG-CBOR codec — serde_cbor, ciborium, ipld usage";
      fingerprint = {
        grep = "serde_cbor";
        lang = "rust";
        filetype = "Cargo.toml";
        tags = [ "cbor" "codec" "ipld" ];
      };
      deps = [ "workspace.member" ];
      emit = "crate-ref";
    }

    # ── Advanced: detect WASM targets ────────────────────────────────────
    {
      id = "target.wasm";
      pattern = "WASM target — wasm-pack, wasm-bindgen, or wasm crate";
      fingerprint = {
        grep = "wasm-bindgen";
        lang = "toml";
        filetype = "Cargo.toml";
        tags = [ "wasm" "target" "web" ];
      };
      deps = [ "workspace.member" ];
      emit = "crate-build";
    }

    # ── Advanced: detect ZK/circuit code ────────────────────────────────
    {
      id = "zk.circuit";
      pattern = "ZK circuit — bellman, halo2, or zkperf usage";
      fingerprint = {
        grep = "zkperf";
        lang = "rust";
        filetype = "Cargo.toml";
        tags = [ "zk" "circuit" "proof" ];
      };
      deps = [ "workspace.member" ];
      emit = "crate-ref";
    }
  ];

  # Topological sort of ideas by their declared deps.
  # Returns { result = [sorted ideas]; cycle = [any cycles found] }
  topoSort = lib:
    let
      g = lib.listToAttrs (map (i: { name = i.id; value = i.deps; }) ideas);
    in
      lib.toposort g;

in {
  inherit ideas topoSort;
}
