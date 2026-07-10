.PHONY: build deploy restart switch logs diagnose clean help tiles

help:
	@echo "Kant Pastebin"
	@echo ""
	@echo "  make build       — Nix build check"
	@echo "  make deploy      — Full deployment (nix build, commit, push, activate, restart)"
	@echo "  make restart     — Restart pastebin + svg2anim-worker services"
	@echo "  make switch      — Build + activate system-manager config"
	@echo "  make logs        — Show error logs"
	@echo "  make diagnose    — Run diagnose script"
	@echo "  make tiles       — Copy DAG-CBOR tiles from dasl-testing"
	@echo "  make clean       — Clean build artifacts"

DASL_TESTING := /mnt/data1/time-2026/02-february/22/dasl/dasl-testing
export DAGCBOR_TILES_PATH := $(DASL_TESTING)/sheaf/tiles/dagcbor_tiles.html

build:
	nix build .#kant-pastebin --no-link

deploy:
	bash deploy.sh deploy

restart:
	systemctl restart kant-pastebin.service || true
	systemctl restart svg2anim-worker.service || true
	systemctl status kant-pastebin.service --no-pager || true
	systemctl status svg2anim-worker.service --no-pager || true

switch:
	bash deploy.sh switch

logs:
	tail -30 logs/kant-pastebin-errors.log 2>/dev/null || echo "  (no error log found)"
	tail -30 logs/nginx-errors.log 2>/dev/null || echo "  (no nginx error log found)"

diagnose:
	bash diagnose.sh

tiles:
	cd $(DASL_TESTING) && python3 sheaf/tiles/build_tiles.py

clean:
	cargo clean
	rm -rf result
