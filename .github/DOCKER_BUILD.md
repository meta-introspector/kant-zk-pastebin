# GitHub Actions Setup

## Required Secrets

Add to repository settings → Secrets and variables → Actions:

1. **DOCKER_HUB_TOKEN**
   - Go to https://hub.docker.com/settings/security
   - Create new access token
   - Copy token value
   - Add as secret in GitHub repo

## Docker Images

Images are pushed to: `h4ckermike/kant-zk-pastebin`

### Tags

- `main` - Latest from main branch
- `sha-<commit>` - Specific commit
- `v1.0.0` - Semantic version tags
- `1.0` - Major.minor version

## Usage

```bash
# Pull latest
docker pull h4ckermike/kant-zk-pastebin:main

# Run
docker run -p 7860:7860 h4ckermike/kant-zk-pastebin:main
```

## Trigger Build

Push to main branch or create a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```
