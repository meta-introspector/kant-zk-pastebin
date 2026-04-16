#!/usr/bin/env bash
# Recursively check git status across all submodules

check_repo() {
    local path="${1:-.}"
    local prefix="${2:-ROOT}"

    # Check for unstaged/untracked changes
    local status
    status=$(git -C "$path" status --porcelain 2>/dev/null) || return

    if [[ -n "$status" ]]; then
        echo ""
        echo "=== $prefix ($path) ==="
        git -C "$path" status --short
    fi

    # Recurse into submodules
    while IFS= read -r line; do
        # Parse: [+- ]<hash> <submodule-path> (<desc>)
        local sub_path
        sub_path=$(echo "$line" | awk '{print $2}')
        [[ -z "$sub_path" ]] && continue

        local full_path="$path/$sub_path"
        [[ -d "$full_path/.git" || -f "$full_path/.git" ]] || continue

        check_repo "$full_path" "$prefix/$sub_path"
    done < <(git -C "$path" submodule status 2>/dev/null)
}

echo "Scanning git tree from: $(pwd)"
check_repo "." "ROOT"
echo ""
echo "Done."
