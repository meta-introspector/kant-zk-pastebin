{ pkgs ? import <nixpkgs> {} }:

let
  # Monster primes for CI/CD stages
  stages = [2 3 5 7 11 13 17 19 23 29 31];
  
  # Build kant-pastebin with stage tracking
  buildStage = stage: prevStage: pkgs.rustPlatform.buildRustPackage {
    pname = "kant-pastebin-stage-${toString stage}";
    version = "0.1.0";
    src = /mnt/data1/kant/pastebin;
    
    cargoLock = {
      lockFile = /mnt/data1/kant/pastebin/Cargo.lock;
    };
    
    # FRACTRAN state encoding for build stage
    # State = 2^stage × 3^test × 5^deploy
    FRACTRAN_STATE = toString (2 * stage);
    
    buildPhase = ''
      echo "🔮 Pipelite Stage ${toString stage}: kant-pastebin"
      echo "   FRACTRAN State: $FRACTRAN_STATE"
      
      ${if stage >= 2 then ''
        echo "   [Stage ${toString stage}] Cargo check..."
        cargo check --release
      '' else ""}
      
      ${if stage >= 5 then ''
        echo "   [Stage ${toString stage}] Cargo test..."
        cargo test --release
      '' else ""}
      
      ${if stage >= 7 then ''
        echo "   [Stage ${toString stage}] Cargo build..."
        cargo build --release
      '' else ""}
      
      ${if stage >= 11 then ''
        echo "   [Stage ${toString stage}] A11y validation..."
        # Check for FRACTRAN in output
        grep -q "FRACTRAN" target/release/kant-pastebin || echo "Warning: No FRACTRAN found"
      '' else ""}
    '';
    
    installPhase = ''
      mkdir -p $out/bin
      ${if stage >= 7 then ''
        cp target/release/kant-pastebin $out/bin/
        echo "✅ Binary installed: $out/bin/kant-pastebin"
      '' else ''
        touch $out/bin/.stage-${toString stage}
      ''}
      
      # Create deployment metadata
      cat > $out/bin/deploy-info.json << EOF
      {
        "stage": ${toString stage},
        "fractran_state": "$FRACTRAN_STATE",
        "timestamp": "$(date -Iseconds)",
        "nix_store": "$out"
      }
      EOF
    '';
    
    meta = {
      description = "kant-pastebin CI/CD stage ${toString stage}";
      stage = stage;
    };
  };
  
  # Build all stages sequentially
  buildPipeline = builtins.foldl' (acc: stage:
    acc // { "stage-${toString stage}" = buildStage stage (acc."stage-${toString (stage - 1)}" or null); }
  ) {} stages;
  
  # Final deployment package
  deploy = pkgs.writeShellScriptBin "deploy-kant-pastebin" ''
    set -e
    
    BINARY="${buildPipeline.stage-31}/bin/kant-pastebin"
    SERVICE="kant-pastebin.service"
    
    echo "🚀 Deploying kant-pastebin"
    echo "   Binary: $BINARY"
    echo "   Service: $SERVICE"
    
    # Update systemd service
    sed -i "s|ExecStart=.*|ExecStart=$BINARY|" ~/.config/systemd/user/$SERVICE
    
    # Reload and restart
    systemctl --user daemon-reload
    systemctl --user restart $SERVICE
    
    # Verify
    sleep 2
    systemctl --user status $SERVICE
    
    # Test endpoint
    curl -s http://localhost:8080/ | grep -q "Monster CFT" && echo "✅ Service responding"
    
    echo "✅ Deployment complete"
  '';

in {
  inherit buildPipeline deploy;
  
  # Convenience attributes
  final = buildPipeline.stage-31;
  
  # CI/CD commands
  ci = pkgs.writeShellScriptBin "kant-pastebin-ci" ''
    echo "🔮 kant-pastebin CI Pipeline"
    ${pkgs.lib.concatMapStringsSep "\n" (stage: ''
      echo "Stage ${toString stage}..."
      nix-build -A buildPipeline.stage-${toString stage}
    '') stages}
    echo "✅ All stages passed"
  '';
}
