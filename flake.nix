{
  description = "Kant Pastebin - UUCP + zkTLS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-ipfs = {
      url = "git+file:///home/mdupont/git/github/dariusc93/rust-ipfs.git?ref=fix/multihash-codetable-yanked";
      flake = false;
    };
    erdfa-publish-src = {
      url = "git+file:///home/mdupont/03-march/17/erdfa-publish";
      flake = false;
    };
    erdfa-clean-src = {
      url = "https://github.com/Escaped-RDFa/namespace.git";
      flake = false;
    };
    erdfa-canonical-src = {
      url = "git+file:///home/mdupont/git/solana.solfunmeme.com/erdfa-canonical.git";
      flake = false;
    };
    zkperf = {
      url = "git+file:///mnt/data1/kant/pastebin/zkperf?ref=353f0b1bb8f78ac37ccd66dfface6a7de25b78cc";
      flake = false;
    };

  };

  outputs = { self, nixpkgs, flake-utils, rust-ipfs, erdfa-publish-src, erdfa-clean-src, erdfa-canonical-src, zkperf }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        kubo = pkgs.kubo;

        # Build a patched source tree with all submodules injected
        patchedSrc = pkgs.runCommand "kant-pastebin-src" {} ''
          cp -r --no-preserve=mode ${self}/. $out
          chmod -R u+w $out
          # Explicitly copy submodule content
          mkdir -p $out/zkperf
          cp -r --no-preserve=mode ${zkperf}/. $out/zkperf
          mkdir -p $out/erdfa-canonical/bindings/rust
          cp -r --no-preserve=mode ${erdfa-publish-src}/. $out/erdfa-canonical/bindings/rust
          mkdir -p $out/erdfa-canonical/bindings/rust/vendor/rust-ipfs
          cp -r --no-preserve=mode ${rust-ipfs}/. $out/erdfa-canonical/bindings/rust/vendor/rust-ipfs
        '';
      in
      {
        packages = {
          kant-pastebin = pkgs.rustPlatform.buildRustPackage {
            pname = "kant-pastebin";
            version = "0.1.0";
            src = patchedSrc;
            cargoLock.lockFile = ./Cargo.lock;
            nativeBuildInputs = [ pkgs.pkg-config pkgs.wasm-pack pkgs.git ];
            buildInputs = [ pkgs.openssl ];
          };

          index-docs = pkgs.writeShellScriptBin "kant-index-docs" ''
            PASTEBIN_URL="http://127.0.0.1:8090/paste"
            DOCS_DIR="$HOME/DOCS"
            SPOOL_DIR="$HOME/spool"

            index_file() {
                local file="$1"
                local title=$(basename "$file")
                local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                
                if [ "$size" -gt 1048576 ]; then return; fi
                
                local content=$(cat "$file" 2>/dev/null || echo "")
                if [ -z "$content" ] || [ ''${#content} -lt 10 ]; then return; fi
                
                local keywords=$(echo "$title" | tr '._-' '\n' | grep -E '^[a-zA-Z0-9]+$' | sort -u | head -10 | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)
                
                echo "Indexing: $title"
                
                local payload=$(${pkgs.jq}/bin/jq -n \
                    --arg t "$title" \
                    --arg c "$content" \
                    --argjson k "$keywords" \
                    '{title:$t,content:$c,keywords:$k}')
                
                ${pkgs.curl}/bin/curl -s -X POST "$PASTEBIN_URL" \
                    -H "Content-Type: application/json" \
                    -d "$payload" | ${pkgs.jq}/bin/jq -r '.id // empty'
            }

            echo "🔍 Indexing ~/DOCS..."
            ${pkgs.findutils}/bin/find "$DOCS_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.org" \) 2>/dev/null | while read f; do
                index_file "$f"
            done

            echo "🔍 Indexing ~/spool..."
            ${pkgs.findutils}/bin/find "$SPOOL_DIR" -maxdepth 2 -type f \( -name "*.md" -o -name "*.txt" \) 2>/dev/null | head -30 | while read f; do
                index_file "$f"
            done

            echo "✅ Indexing complete!"
          '';

          default = self.packages.${system}.kant-pastebin;
          
          systemd-service = pkgs.writeTextFile {
            name = "kant-pastebin.service";
            text = ''
              [Unit]
              Description=Kant Pastebin - UUCP + zkTLS + IPFS
              After=network.target

              [Service]
              Type=simple
              WorkingDirectory=/mnt/data1/kant/pastebin
              ExecStart=${self.packages.${system}.kant-pastebin}/bin/kant-pastebin
              Restart=always
              RestartSec=10
              Environment="BIND_ADDR=127.0.0.1:8090"
              Environment="UUCP_SPOOL=/mnt/data1/spool/uucp/pastebin"
              Environment="RUST_LOG=info"
              Environment="BASE_URL=\${KANT_BASE_URL:-https://solana.solfunmeme.com}"
              Environment="BASE_PATH=/pastebin"
              Environment="PATH=${kubo}/bin"

              [Install]
              WantedBy=default.target
            '';
          };

          index-docs-service = pkgs.writeTextFile {
            name = "kant-index-docs.service";
            text = ''
              [Unit]
              Description=Index DOCS and spool to Kant Pastebin
              After=kant-pastebin.service

              [Service]
              Type=oneshot
              ExecStart=${self.packages.${system}.index-docs}/bin/kant-index-docs
              StandardOutput=journal
              StandardError=journal

              [Install]
              WantedBy=default.target
            '';
          };

          index-docs-timer = pkgs.writeTextFile {
            name = "kant-index-docs.timer";
            text = ''
              [Unit]
              Description=Index DOCS and spool daily
              Requires=kant-index-docs.service

              [Timer]
              OnCalendar=daily
              Persistent=true

              [Install]
              WantedBy=timers.target
            '';
          };

        };

        apps = {
          kant-pastebin = {
            type = "app";
            program = "${self.packages.${system}.kant-pastebin}/bin/kant-pastebin";
          };
          default = self.apps.${system}.kant-pastebin;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cargo
            rustc
            rust-analyzer
            rustfmt
            clippy
            pkg-config
            openssl
            nodejs
            chromium
            wasm-pack
          ];
          shellHook = ''
            export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1
            export PUPPETEER_EXECUTABLE_PATH=${pkgs.chromium}/bin/chromium
          '';
        };
      }
    );
}
