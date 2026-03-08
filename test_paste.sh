#!/usr/bin/env bash
# Test paste module

cd /mnt/data1/kant/pastebin
cargo test --lib 2>&1 | tail -20
