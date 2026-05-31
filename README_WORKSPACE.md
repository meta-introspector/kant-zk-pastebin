# Custom-File-Crawler Workspace

This is a clean workspace for the Custom-File-Crawler project, created from the original repository at `/home/mdupont/git/solana.solfunmeme.com/Custom-File-Crawler.git`.

## Setup Instructions

### Prerequisites
- Nix package manager must be installed
- Git must be installed

### Quick Setup

1. **Clone the workspace** (if not already done):
   ```bash
   cd /mnt/data1/time-2026/04-april/10/vibe-experiment
   git clone /home/mdupont/git/solana.solfunmeme.com/Custom-File-Crawler.git Custom-File-Crawler-workspace
   cd Custom-File-Crawler-workspace
   ```

2. **Run the setup script**:
   ```bash
   ./setup_workspace.sh
   ```

### Manual Setup (if script fails)

1. Update submodules:
   ```bash
   git submodule update --init --recursive
   ```

2. Fix erdfa-publish submodule:
   ```bash
   cd libs/erdfa-canonical/bindings/rust
   git remote add bare /mnt/data1/git/solana.solfunmeme.com/erdfa-publish.git
   git fetch bare
   git checkout 16d55dae3e64a65a40bfbad8a568f04afbc611d4
   cd ../../..
   ```

3. Fix zkperf submodule:
   ```bash
   cd zkperf
   git remote add bare-local /mnt/data1/git/github.com/meta-introspector/zkperf.git
   git fetch bare-local
   git checkout e594839557e3db5c9684758bdf0b600c4906d0ba
   cd ..
   ```

4. Build the project:
   ```bash
   make build
   ```

## Development

### Building
```bash
make build  # Uses nix develop -c cargo build
```

### Running
```bash
cargo run --bin main -- --help  # Show help
cargo run --bin main -- /path/to/scan  # Scan a directory
```

### Testing
```bash
cargo test
```

## Project Structure

- `src/` - Main source code
- `libs/erdfa-canonical/` - ERDFA canonical library (submodule)
- `zkperf/` - ZK performance library (submodule)
- `output/` - Output directory for reports
- `setup_workspace.sh` - Setup script
- `Makefile` - Build targets

## Troubleshooting

### Submodule issues
If you get errors about missing commits in submodules:
1. Check that all remotes are properly configured
2. Run `git fetch --all` in the problematic submodule
3. Try checking out the specific commit hash mentioned in the error

### Nix issues
If `make build` fails with Nix errors:
1. Ensure Nix is properly installed: `nix --version`
2. Try `nix develop` to enter the development environment manually
3. Then run `cargo build` inside the Nix shell

### Missing dependencies
The project requires various system libraries. The Nix environment should provide most of them, but if you encounter missing library errors, you may need to install them system-wide.

## Updating from Original Repository

To pull updates from the original repository:
```bash
git remote add original /mnt/data1/time-2026/04-april/06/Custom-File-Crawler
git fetch original
git merge original/main
```

Then run the setup script again to update submodules:
```bash
./setup_workspace.sh
```