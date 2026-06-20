.PHONY: build deploy run test-share-menu clean help tiles

help:
	@echo "Kant Pastebin"
	@echo ""
	@echo "  make build       — Build (nix build)"
	@echo "  make run         — Run with cargo"
	@echo "  make test-share-menu — Run offline share menu test"
	@echo "  make deploy      — Deploy with systemd"
	@echo "  make tiles       — Copy DAG-CBOR tiles from dasl-testing"
	@echo "  make clean       — Clean build artifacts"

DASL_TESTING := /mnt/data1/time-2026/02-february/22/dasl/dasl-testing
export DAGCBOR_TILES_PATH := $(DASL_TESTING)/sheaf/tiles/dagcbor_tiles.html

build:
	nix develop -c cargo build

run:
	nix develop -c cargo run

test-share-menu:
	nix develop -c cargo run --bin kant-pastebin -- test-share-menu

deploy: build
	bash deploy.sh

tiles:
	cd $(DASL_TESTING) && python3 sheaf/tiles/build_tiles.py

clean:
	cargo clean
	rm -rf result
