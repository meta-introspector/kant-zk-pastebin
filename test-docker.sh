#!/bin/bash
# Test Docker build locally

echo "=== Building Docker image ==="
docker build -t kant-pastebin-test .

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "To run locally:"
    echo "  docker run -p 7860:7860 kant-pastebin-test"
    echo ""
    echo "Then visit: http://localhost:7860"
else
    echo "❌ Build failed"
    exit 1
fi
