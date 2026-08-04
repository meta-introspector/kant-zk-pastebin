.PHONY: help build run deploy restart switch logs diagnose clean tiles \
	svg-queue svg-worker-start svg-worker-status svg-cli-build \
	task-gif-lookup task-deploy-verify task-worker-fix task-perm-fix \
	sm-update sm-build sm-switch

PASTEBIN_DIR := /mnt/data1/kant/pastebin
SM_DIR       := /home/mdupont/projects/system-manager
DASL_TESTING := /mnt/data1/time-2026/02-february/22/dasl/dasl-testing
export DAGCBOR_TILES_PATH := $(DASL_TESTING)/sheaf/tiles/dagcbor_tiles.html

TASK_RUNNER := /home/mdupont/dotagents/target/release/task-runner
DEEPSEEK_ENV := /home/mdupont/.deepseek/env.sh

help:
	@echo "Kant Pastebin"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build       — Nix build (nix build .#kant-pastebin)"
	@echo "  make dev         — Cargo build via nix develop"
	@echo "  make run         — Run via nix develop"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy      — Full deployment (nix build, commit, push, activate, restart)"
	@echo "  make restart     — Restart pastebin + svg2anim-worker services"
	@echo "  make switch      — Build + activate system-manager config"
	@echo ""
	@echo "System-Manager:"
	@echo "  make sm-update   — Update pastebin-src in system-manager flake.lock"
	@echo "  make sm-build    — Build system-manager all-services config"
	@echo "  make sm-switch   — Activate system-manager config (sudo)"
	@echo ""
	@echo "Diagnostics:"
	@echo "  make logs        — Show error logs"
	@echo "  make diagnose    — Run diagnose script"
	@echo "  make clean       — Clean build artifacts"
	@echo ""
	@echo "Tiles & SVG:"
	@echo "  make tiles           — Copy DAG-CBOR tiles from dasl-testing"
	@echo "  make svg-queue       — Queue animated SVGs"
	@echo "  make svg-worker-start  — Start svg2anim-worker via systemd"
	@echo "  make svg-worker-status — Check svg2anim-worker status"
	@echo "  make svg-cli-build    — Build svg2tile-cli binary"
	@echo ""
	@echo "Tasks:"
	@echo "  make task-gif-lookup   — GIF lookup fix"
	@echo "  make task-deploy-verify — Deploy+verify"
	@echo "  make task-worker-fix   — Worker .failed suffix fix"
	@echo "  make task-perm-fix     — /tmp PermissionDenied fix"

# ── Build & Run ──

build:
	nix build .#kant-pastebin --no-link

dev:
	nix develop -c cargo build --release

run:
	nix develop -c cargo run --release

# ── Deploy ──

deploy:
	bash deploy.sh deploy

restart:
	systemctl restart kant-pastebin.service || true
	systemctl restart svg2anim-worker.service || true
	systemctl status kant-pastebin.service --no-pager || true
	systemctl status svg2anim-worker.service --no-pager || true

switch:
	bash deploy.sh switch

# ── System-Manager ──

sm-update:
	cd $(SM_DIR) && nix flake update pastebin-src

sm-build:
	cd $(SM_DIR) && nix build .#systemConfigs.all-services --no-link

sm-switch:
	sudo system-manager switch --flake $(SM_DIR)#all-services

# ── Diagnostics ──

logs:
	tail -30 logs/kant-pastebin-errors.log 2>/dev/null || echo "  (no error log found)"
	tail -30 logs/nginx-errors.log 2>/dev/null || echo "  (no nginx error log found)"

diagnose:
	bash diagnose.sh

clean:
	cargo clean
	rm -rf result

# ── Tiles & SVG ──

tiles:
	cd $(DASL_TESTING) && python3 sheaf/tiles/build_tiles.py

svg-queue:
	bash ./scripts/svg2anim-queue.sh

svg-worker-start:
	sudo systemctl daemon-reload || true
	sudo systemctl enable svg2anim-worker.service || true
	sudo systemctl start svg2anim-worker.service || true

svg-worker-status:
	systemctl status svg2anim-worker.service --no-pager || true

svg-cli-build:
	cargo build --manifest-path tools/svg2tile-cli/Cargo.toml --release

# ── Tasks ──

task-gif-lookup:
	bash -c 'source $(DEEPSEEK_ENV) && \
		$(TASK_RUNNER) run \
			--task /home/mdupont/dotagents/tasks/svg2anim-fix-get-file-gif-lookup \
			--agent pi --mode oneshot --verbose'

task-deploy-verify:
	bash -c 'source $(DEEPSEEK_ENV) && \
		$(TASK_RUNNER) run \
			--task /home/mdupont/dotagents/tasks/svg2anim-complete-deploy-and-verify \
			--agent pi --mode oneshot --verbose'

task-worker-fix:
	bash -c 'source $(DEEPSEEK_ENV) && \
		$(TASK_RUNNER) run \
			--task /home/mdupont/dotagents/tasks/svg2anim-worker-fix-failed-suffix \
			--agent pi --mode oneshot --verbose'

task-perm-fix:
	bash -c 'source $(DEEPSEEK_ENV) && \
		$(TASK_RUNNER) run \
			--task /home/mdupont/dotagents/tasks/svg2anim-fix-permission-denied \
			--agent pi --mode oneshot --verbose'
