# Hugging Face Deployment Guide

## Quick Deploy

```bash
./deploy-hf.sh
```

## Manual Steps

### 1. Create Hugging Face Space

1. Go to https://huggingface.co/new-space
2. Name: `kant-pastebin`
3. SDK: **Docker**
4. Hardware: CPU basic (free tier works)

### 2. Clone and Deploy

```bash
# Clone your space
git clone https://huggingface.co/spaces/YOUR_USERNAME/kant-pastebin
cd kant-pastebin

# Copy deployment files
cp ../Dockerfile .
cp ../docker-entrypoint.sh .
cp ../README-HF.md README.md
cp -r ../src .
cp ../Cargo.toml ../Cargo.lock .

# Commit and push
git add .
git commit -m "Initial deployment with embedded IPFS"
git push
```

### 3. Wait for Build

Hugging Face will automatically build and deploy your Docker container.

## Features

✅ **Embedded IPFS** - No external daemon needed
✅ **Persistent Storage** - Data stored in `/data`
✅ **Port 7860** - Standard Hugging Face port
✅ **Offline Mode** - IPFS runs in offline mode for speed

## Environment Variables

Set in Space settings if needed:

- `BIND_ADDR` - Default: `0.0.0.0:7860`
- `UUCP_SPOOL` - Default: `/data/pastebin`
- `IPFS_PATH` - Default: `/data/ipfs`

## Local Testing

```bash
docker build -t kant-pastebin .
docker run -p 7860:7860 -v $(pwd)/data:/data kant-pastebin
```

Visit: http://localhost:7860
