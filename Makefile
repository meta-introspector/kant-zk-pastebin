.PHONY: build deploy check test test-extended test-all deps update-lock \
        test-js test-html test-generators test-comprehensive test-plugins \
        test-report test-all-coverage help

help:
	@echo "Kant Pastebin - Test Suite"
	@echo ""
	@echo "Quick Commands:"
	@echo "  make test-all-coverage  - Run all tests and generate report"
	@echo "  ./run-all-tests.sh      - Master test orchestrator"
	@echo ""
	@echo "Individual Tests:"
	@echo "  make test-js            - Test JavaScript parser"
	@echo "  make test-html          - Test HTML parser"
	@echo "  make test-css           - Test CSS parser"
	@echo "  make test-generators    - Test data generators"
	@echo "  make test-website       - Test website integration"
	@echo "  make test-fuzz-frontend - Test frontend fuzzer"
	@echo ""
	@echo "Comprehensive:"
	@echo "  make test-comprehensive - Coverage + fuzz + perf tests"
	@echo "  make test-plugins       - Test all plugins"
	@echo "  make test-report        - Generate HTML report"
	@echo ""
	@echo "Build & Deploy:"
	@echo "  make build              - Build with Nix"
	@echo "  make deploy             - Deploy to server"
	@echo "  make check              - Check compilation"
	@echo ""
	@echo "See TEST_SUITE.md for detailed documentation"

build:
	nix build

cargo-build:
	nix develop -c cargo build

update-lock:
	nix develop -c cargo update

deploy: build
	bash deploy.sh

check:
	nix develop --command cargo check

deps:
	nix develop --command npm ci

test: deps
	nix develop --command node test-pastebin.js

test-extended: deps
	nix develop --command node test-extended.js

test-all: deps
	nix develop --command bash -c 'node test-pastebin.js && node test-extended.js'

test-js:
	nix develop --command bash -c '\
		cargo run --bin js_parser -- test-fixtures/sample.js && \
		cargo run --bin js_interpreter'

test-html:
	nix develop --command bash -c '\
		cargo run --bin html_parser -- test-fixtures/sample.html'

test-generators:
	nix develop --command cargo run --bin test_generator

test-css:
	nix develop --command cargo run --bin css_parser -- test-fixtures/sample.css

test-website:
	nix develop --command cargo run --bin website_test

test-fuzz-frontend:
	nix develop --command cargo run --bin fuzz_frontend

test-bins: test-js test-html test-generators test-css test-website test-fuzz-frontend

test-zkperf:
	./test-with-zkperf.sh

test-all-coverage: test-bins test-zkperf
	@echo "✅ All tests completed"
	@echo "📊 zkPerf witnesses: test-recordings/*.perf.data"
	@echo "📄 Report: zkperf-test-report.json"
