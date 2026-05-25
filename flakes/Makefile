# Makefile for microflake Cargo.lock generation
#
# Usage:
#   make zkperf-witness-lock   # Generate Cargo.lock for zkperf-witness
#   make zos-circuit-lock      # Generate Cargo.lock for zos-circuit-optimizer
#   make all-locks             # Generate all Cargo.locks
#
# Each target creates a temporary workspace in _gen/ with the path deps,
# runs cargo generate-lockfile, copies the result to the flake dir.

.SILENT:
.PHONY: all-locks clean-gen

all-locks: zkperf-witness-lock zos-circuit-lock

# ── zkperf-witness ───────────────────────────────────────────
# Deps: zkperf-macros at ../zkperf-macros (relative to its dir)
zkperf-witness-lock:
	rm -rf _gen/zkperf-witness && mkdir -p _gen/zkperf-witness/zkperf
	cp -r ../zkperf/zkperf-witness _gen/zkperf-witness/zkperf/
	cp -r ../zkperf/zkperf-macros _gen/zkperf-witness/zkperf/
	printf '%s\n' '[workspace]' 'members = ["zkperf/zkperf-witness", "zkperf/zkperf-macros"]' 'resolver = "2"' > _gen/zkperf-witness/Cargo.toml
	cd _gen/zkperf-witness && cargo generate-lockfile 2>&1 | sed 's/^/    /'
	cp _gen/zkperf-witness/Cargo.lock zkperf-witness/
	rm -rf _gen/zkperf-witness
	@echo "  ✓ zkperf-witness/Cargo.lock generated"

# ── zos-circuit-optimizer ─────────────────────────────────────
# Deps: erdfa-dasl at ../erdfa-dasl, zkperf-macros at ../../zkperf/zkperf-macros
# (relative to plugins/zos-circuit-optimizer)
zos-circuit-lock:
	rm -rf _gen/zos-circuit && mkdir -p _gen/zos-circuit/zkperf
	cp -r ../plugins/zos-circuit-optimizer _gen/zos-circuit/
	cp -r ../plugins/erdfa-dasl _gen/zos-circuit/
	cp -r ../zkperf/zkperf-macros _gen/zos-circuit/zkperf/
	printf '%s\n' '[workspace]' 'members = ["zos-circuit-optimizer", "erdfa-dasl", "zkperf/zkperf-macros"]' 'resolver = "2"' > _gen/zos-circuit/Cargo.toml
	cd _gen/zos-circuit && cargo generate-lockfile 2>&1 | sed 's/^/    /'
	cp _gen/zos-circuit/Cargo.lock zos-circuit-optimizer/
	rm -rf _gen/zos-circuit
	@echo "  ✓ zos-circuit-optimizer/Cargo.lock generated"

clean-gen:
	rm -rf _gen/
