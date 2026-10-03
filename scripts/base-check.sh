#!/usr/bin/env bash
# base-check.sh — establish what the base actually contains, before reading a
# diff or branching off it.
#
# Both mistakes made on 2026-10-03 were the same shape: acting on a stale
# picture of the base. Reviewing PR #1 produced two confident, wrong findings
# because the PR was already merged. Then PR #11 hardened a sink that had been
# removed upstream, because the branch was cut 213 commits stale.
#
# The second one had a tell on screen: GitHub reported 645 changed files for a
# commit that touched one. That number was read and not treated as
# information. So this script checks the *shape* of a diff before its contents,
# which is cheaper than discovering the problem after writing a fix.
#
# Usage:
#   scripts/base-check.sh <pr-number>          check a PR before reviewing it
#   scripts/base-check.sh --branch <name>      check a local branch before pushing
#
# Exit 0 if the base looks right, 1 if something needs a human.

set -uo pipefail

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
warn() { printf '%s\n' "${YEL}!${OFF} $*"; }
bad()  { printf '%s\n' "${RED}x${OFF} $*"; }
ok()   { printf '%s\n' "${GRN}ok${OFF} $*"; }
note() { printf '%s\n' "${DIM}  $*${OFF}"; }

need() { command -v "$1" >/dev/null 2>&1 || { bad "missing required tool: $1"; exit 2; }; }
need git; need gh

# Check 0 -------------------------------------------------------------------
# Is the local `main` the same as `origin/main`?
#
# In this repo it is NOT: local `main` is "ahead 59, behind 213". Any check
# written as `git merge-base --is-ancestor <sha> main` is therefore answering a
# question about a stale divergent branch, and will confidently report the wrong
# thing. This is not hypothetical -- it produced a false "already merged" claim
# about PR #1, and a review that retracted two correct findings because of it.
#
# So: every check below names `origin/<branch>` explicitly, and this runs first
# to say out loud when the local name would have given a different answer.
check_ref_divergence() {
  local divergence
  divergence=$(git rev-list --left-right --count main...origin/main 2>/dev/null) || {
    note "no local main to compare"; return 0; }
  # rev-list --left-right --count prints TAB-separated "ahead<TAB>behind".
  local ahead="${divergence%%	*}"
  local behind="${divergence##*	}"
  if [ "${ahead:-0}" -eq 0 ] && [ "${behind:-0}" -eq 0 ]; then
    ok "local main matches origin/main"
    return 0
  fi
  bad "local 'main' has DIVERGED from origin/main (ahead ${ahead:-?}, behind ${behind:-?})"
  note "A check written against 'main' is measuring the wrong branch."
  note "Use 'origin/main' explicitly. This is not a warning to ignore --"
  note "it has already produced one confidently wrong answer."
  return 1
}

# Check 1 -------------------------------------------------------------------
# Is the PR already merged? Always against origin/<base>, never the local name.
check_merged() {
  local sha="$1" label="$2" base_ref="$3"
  if git merge-base --is-ancestor "$sha" "origin/$base_ref" 2>/dev/null; then
    bad "$label is ALREADY an ancestor of origin/$base_ref."
    note "Its code has landed, so a diff against it is history, not a change"
    note "under review. Do not report defects in it -- check first whether"
    note "later commits already fixed whatever you find."
    return 1
  fi
  # Where does it actually live? Cheap, and it distinguishes "not merged" from
  # "landed somewhere else", which have very different follow-ups.
  local homes=""
  local r
  for r in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null); do
    git merge-base --is-ancestor "$sha" "$r" 2>/dev/null && homes="$homes ${r#origin/}"
  done
  ok "$label is not merged into origin/$base_ref"
  if [ -n "$homes" ]; then
    note "its commit IS an ancestor of:$homes"
    note "so 'not merged into base' and 'landed elsewhere' are both true."
  fi
  return 0
}

# Check 2 -------------------------------------------------------------------
# How stale is what we are reading? A large number is not itself a failure, but
# it means line numbers and file contents cannot be trusted.
check_staleness() {
  local base="$1"
  local behind
  behind=$(git rev-list --count "$base"..origin/main 2>/dev/null) || {
    warn "could not measure staleness of $base"; return 0; }
  if [ "$behind" -eq 0 ]; then
    ok "base is current with origin/main"
    return 0
  fi
  warn "base $base is ${behind} commits behind origin/main"
  note "Line numbers, file contents and diffs against it may all be wrong."
  note "Re-fetch and re-read before quoting a line number or writing a fix."
  return 0
}

# Check 3 -------------------------------------------------------------------
# Does the diff have the shape we expect? This is the cheapest check and the
# one that was skipped. A one-file change reported as hundreds of files means
# the base is wrong.
check_shape() {
  local ref="$1" expect="${2:-}"
  local files
  files=$(git diff --name-only "origin/main...$ref" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$files" -eq 0 ]; then
    note "0 files differ from origin/main"
    return 0
  fi
  if [ -n "$expect" ] && [ "$files" != "$expect" ]; then
    bad "expected $expect changed file(s), found $files"
    note "If that is not deliberate, the base is wrong -- not the content."
    note "Inspect with:  git diff --stat origin/main...$ref | tail -20"
    return 1
  fi
  if [ "$files" -gt 20 ]; then
    warn "$files files differ from origin/main -- much larger than a typical fix"
    note "Confirm this is intended before reading any of the content."
  else
    ok "$files file(s) differ from origin/main"
  fi
  return 0
}

rc=0

case "${1:-}" in
  --branch)
    branch="${2:-}"
    [ -z "$branch" ] && { bad "usage: $0 --branch <name>"; exit 2; }
    git fetch --quiet origin main 2>/dev/null || true
    base=$(git merge-base "origin/main" "$branch" 2>/dev/null) || {
      bad "no merge base for $branch"; exit 1; }
    printf '%s\n' "${DIM}base-check: $branch${OFF}"
    check_ref_divergence || rc=1
    check_staleness "$base" || rc=1
    check_shape "$branch" || rc=1
    ;;
  ""|--help|-h)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    pr="$1"
    git fetch --quiet origin main 2>/dev/null || true
    sha=$(gh pr view "$pr" --json headRefOid --jq .headRefOid 2>/dev/null) || {
      bad "could not read PR #$pr"; exit 2; }
    base_ref=$(gh pr view "$pr" --json baseRefName --jq .baseRefName 2>/dev/null)
    state=$(gh pr view "$pr" --json state --jq .state 2>/dev/null)
    printf '%s\n' "${DIM}base-check: PR #$pr ($state -> $base_ref)${OFF}"
    note "head $sha"
    check_ref_divergence || rc=1
    check_merged "$sha" "PR #$pr" "$base_ref" || rc=1
    if [ "$base_ref" = "main" ]; then
      check_staleness "$(git merge-base origin/main "$sha" 2>/dev/null || echo "$sha")" || rc=1
    fi
    ;;
esac

if [ "$rc" -eq 0 ]; then
  printf '\n%s\n' "${GRN}base looks sane. Proceed -- but confirm the diff's shape first.${OFF}"
else
  printf '\n%s\n' "${RED}base does not look sane. Do not review or fix against this yet.${OFF}"
fi
exit "$rc"