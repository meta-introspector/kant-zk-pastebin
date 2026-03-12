#!/bin/bash
# Deploy to Hugging Face Spaces

SPACE_NAME="kant-pastebin"
HF_USERNAME="${HF_USERNAME:-your-username}"

echo "=== Preparing Hugging Face Deployment ==="

# Create deployment directory
mkdir -p hf-deploy
cd hf-deploy

# Copy necessary files
cp ../Dockerfile .
cp ../docker-entrypoint.sh .
cp ../README-HF.md README.md
cp -r ../src .
cp ../Cargo.toml ../Cargo.lock .

echo "=== Files ready in hf-deploy/ ==="
echo ""
echo "Next steps:"
echo "1. Create a Space on Hugging Face: https://huggingface.co/new-space"
echo "2. Choose 'Docker' as SDK"
echo "3. Clone the space:"
echo "   git clone https://huggingface.co/spaces/$HF_USERNAME/$SPACE_NAME"
echo "4. Copy files:"
echo "   cp -r hf-deploy/* $SPACE_NAME/"
echo "5. Push:"
echo "   cd $SPACE_NAME && git add . && git commit -m 'Initial deployment' && git push"
