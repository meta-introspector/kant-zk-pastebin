.PHONY: build deploy check test test-extended test-all deps update-lock \
        test-js test-html test-generators

build:
	nix build

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

test-bins: test-js test-html test-generators test-css test-website
