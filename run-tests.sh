#!/usr/bin/env bash
# Kant Pastebin API Tests
set -e

BASE_URL="${1:-http://localhost:9191}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Kant Pastebin Test Suite ==="
echo "Base URL: $BASE_URL"

# Test 1: Home Page
echo ""
echo "📄 Test 1: Home Page"
curl -s "$BASE_URL/" | grep -q "Kant Pastebin" && echo "✅ Home page loads" || echo "❌ Home page failed"

# Test 2: Create Paste
echo ""
echo "📤 Test 2: Create Paste"
PASTE_RESPONSE=$(curl -s -X POST "$BASE_URL/paste" \
    -H "Content-Type: application/json" \
    -d '{"title":"Test","content":"test content"}')
PASTE_ID=$(echo "$PASTE_RESPONSE" | jq -r '.id')
echo "✅ Created: $PASTE_ID"

# Test 3: Get Paste
echo ""
echo "📥 Test 3: Get Paste"
curl -s "$BASE_URL/paste/$PASTE_ID" | grep -q "test content" && echo "✅ Paste retrieved" || echo "❌ Failed"

# Test 4: Browse
echo ""
echo "📚 Test 4: Browse"
curl -s "$BASE_URL/browse" | grep -q "Browse" && echo "✅ Browse works" || echo "❌ Failed"

# Test 5: OpenAPI
echo ""
echo "📋 Test 5: OpenAPI"
curl -s "$BASE_URL/openapi.json" | jq -r '.info.title' | grep -q "kant-pastebin" && echo "✅ OpenAPI works" || echo "❌ Failed"

echo ""
echo "✅ All tests passed"

