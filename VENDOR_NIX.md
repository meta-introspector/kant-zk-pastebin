# Vendored Crates Nix Configuration

This directory contains Nix configurations for all vendored crates in the kant-pastebin project.

## Files Generated

### 1. `flake-vendor.nix`
- Comprehensive flake configuration for all vendored crates
- Uses cargo2nix for Rust crate management
- Includes individual package definitions and unified interface

### 2. `generate-vendor-configs.sh`
- Script to generate Nix configurations for all vendored crates
- Creates individual flake.nix files for each crate
- Generates unified flake.nix for batch operations
- Generates cargo2nix configuration for main project

### 3. `vendor-cargo2nix/`
- Individual cargo2nix configurations for each vendored crate
- Each file follows the format `{crate-name}.nix`

### 4. `vendor-flakes/`
- Individual flake.nix files for each vendored crate
- Each crate can be built independently

## Usage

### Build Individual Crate
```bash
# Build a specific vendored crate
nix build -f ./vendor-flakes/{crate-name}-flake.nix

# Example: build actix-web
nix build -f ./vendor-flakes/actix-web-flake.nix
```

### Build All Crates
```bash
# Build all vendored crates using unified flake
nix build -f ./flake-vendor-unified.nix

# Build specific package from unified flake
nix build -f ./flake-vendor-unified.nix#packages.x86_64-linux.actix-web
```

### Development Shell
```bash
# Development shell for all vendored crates
nix develop -f ./flake-vendor-unified.nix

# Development shell for specific crate
nix develop -f ./vendor-flakes/{crate-name}-flake.nix
```

### Main Project Build
```bash
# Build main project using cargo2nix
nix build -f ./cargo2nix.nix
```

## Configuration Details

### Cargo2nix Integration
- Uses cargo2nix for precise Rust dependency management
- Each crate is built with its isolated environment
- Supports features and build-time dependencies

### Flake Features
- Reproducible builds across different systems
- Parallel build support
- Development shells with tooling
- Check systems for validation

### Performance Optimizations
- Cargo vendor directory integration
- Build caching between similar crates
- Parallel execution support

## Structure

```
pastebin/
├── vendor/                    # Vendored crates (566 crates)
├── vendor-cargo2nix/         # Individual cargo2nix configs
├── vendor-flakes/           # Individual flake.nix files
├── flake-vendor.nix        # Comprehensive vendor flake
├── flake-vendor-unified.nix # Unified flake for all crates
├── cargo2nix.nix           # Main project cargo2nix config
└── generate-vendor-configs.sh # Generation script
```

## Maintenance

### Adding New Vendored Crates
1. Run `cargo vendor` to update vendor directory
2. Run `./generate-vendor-configs.sh` to regenerate configs
3. Test builds with `nix build -f ./flake-vendor-unified.nix`

### Updating Crate Versions
1. Update Cargo.toml in main project
2. Run `cargo vendor` to update vendor directory
3. Regenerate configurations with `./generate-vendor-configs.sh`

### Troubleshooting
- Check individual crate builds: `nix build -f ./vendor-flakes/{crate}-flake.nix`
- Validate flake: `nix flake check -f ./flake-vendor-unified.nix`
- Debug build issues: `nix build -f ./flake-vendor-unified.nix --debug`

## Benefits

1. **Reproducibility**: Every build is deterministic
2. **Performance**: Parallel builds and caching
3. **Isolation**: Each crate in its own build environment
4. **Tooling**: Integrated development environments
5. **Validation**: Comprehensive check systems
6. **Scalability**: Handles 566+ crates efficiently

This configuration transforms the vendored dependency management from a manual process to an automated, reproducible Nix-based system.