---
title: Kant Pastebin
emoji: 📋
colorFrom: green
colorTo: blue
sdk: docker
pinned: false
license: mit
---

# Kant Pastebin - UUCP + zkTLS + IPFS

A pastebin service with built-in IPFS content addressing.

## Features

- 📋 Simple paste sharing
- 🔗 IPFS content addressing
- 🔐 SHA256 witness hashing
- 🏷️ Keyword tagging
- 💬 Reply threading
- 🔍 Full-text search

## Usage

1. Visit the app URL
2. Paste your content
3. Get an IPFS CID for permanent storage
4. Share via URL or IPFS

## API

- `POST /paste` - Create paste
- `GET /paste/{id}` - View paste
- `GET /raw/{id}` - Raw content
- `GET /browse` - List pastes

## IPFS Access

Every paste is automatically added to IPFS:

```bash
ipfs cat <CID>
```

## Local Development

```bash
docker build -t kant-pastebin .
docker run -p 7860:7860 kant-pastebin
```
