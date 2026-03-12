#!/bin/bash
BASE=http://localhost:8090
get() { curl -s "$BASE$1"; }
check() { get "$1" | grep -q "$2" && echo "✅ $3" || echo "❌ $3"; }

check / FRACTRAN "FRACTRAN code"
check / aria-label "ARIA labels"
check / tabindex "Tab navigation"
check / onkeydown "Keyboard handlers"
check /browse a11y-live "Live region"
check /paste/20260309_153124_untitled_this_symmetry_structural_mathematical_content "reply-btn.*aria-label" "Reply buttons"
