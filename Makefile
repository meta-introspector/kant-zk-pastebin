.PHONY: build deploy restart switch logs diagnose clean help tiles \
	task-gif-lookup task-deploy-verify task-worker-fix task-perm-fix \
	svg-queue svg-worker-start svg-worker-status svg-cli-build

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
	@echo "  make svg-queue        — Queue animated SVGs from ~/aristotle-results/all_svg.txt"
	@echo "  make svg-worker-start — Start svg2anim-worker via systemd"
	@echo "  make svg-worker-status — Check svg2anim-worker status"
	@echo "  make svg-cli-build    — Build svg2tile-cli binary via cargo"
	@echo "  make task-gif-lookup   — Run GIF lookup fix task via task-runner"
	@echo "  make task-deploy-verify — Run deploy+verify task via task-runner"
	@echo "  make task-worker-fix   — Run worker .failed suffix fix task via task-runner"
	@echo "  make task-perm-fix     — Run /tmp PermissionDenied fix task via task-runner"

DASL_TESTING := /mnt/data1/time-2026/02-february/22/dasl/dasl-testing
export DAGCBOR_TILES_PATH := $(DASL_TESTING)/sheaf/tiles/dagcbor_tiles.html

TASK_RUNNER := /home/mdupont/dotagents/target/release/task-runner
DEEPSEEK_ENV := /home/mdupont/.deepseek/env.sh

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

svg-queue:
	bash ./scripts/svg2anim-queue.sh

svg-worker-start:
	sudo systemctl daemon-reload || true
	sudo systemctl enable svg2anim-worker.service || true
	sudo systemctl start svg2anim-worker.service || true

svg-worker-status:
	systemctl status svg2anim-worker.service --no-pager || true

svg-cli-build:
	cargo build --bin svg2tile-cli --release

clean:
	cargo clean
	rm -rf result
