.PHONY: build deploy check test test-extended test-all deps update-lock

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
