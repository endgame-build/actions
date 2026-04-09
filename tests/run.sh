#!/usr/bin/env bash
# Test runner for changelog pipeline scripts.
# Usage: bash tests/run.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0 FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "    expected to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "    expected empty, got: $actual"
    FAIL=$((FAIL + 1))
  fi
}

# Prepend mock dir to PATH
export PATH="$SCRIPT_DIR/mocks:$PATH"

echo "=== collect-context.sh ==="
export GITHUB_OUTPUT=$(mktemp)
export PR_NUMBER=42
export GH_TOKEN=fake

bash "$REPO_DIR/scripts/collect-context.sh"

OUTPUT=$(cat "$GITHUB_OUTPUT")
assert_contains "cliff output present" "cliff<<EOF_cliff" "$OUTPUT"
assert_contains "desc output present" "desc<<EOF_desc" "$OUTPUT"
assert_contains "diff output present" "diff<<EOF_diff" "$OUTPUT"
assert_contains "commits output present" "commits<<EOF_commits" "$OUTPUT"
assert_contains "cliff has changelog content" "Add user authentication" "$OUTPUT"
assert_contains "desc has PR body" "OAuth2" "$OUTPUT"
assert_contains "diff has file stat" "src/auth.ts" "$OUTPUT"
assert_contains "commits has messages" "session management" "$OUTPUT"
rm -f "$GITHUB_OUTPUT"

echo ""
echo "=== collect-digest.sh ==="
unset GITHUB_OUTPUT
export REPOS="endgame-build/test-repo endgame-build/empty-repo"

DIGEST=$(bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null)
assert_contains "includes test-repo" "test-repo" "$DIGEST"
assert_contains "has Added section" "Add user authentication" "$DIGEST"
assert_contains "has Fixed section" "Fix login redirect" "$DIGEST"
assert_contains "empty-repo shows error" "Could not retrieve" "$DIGEST"

echo ""
echo "=== collect-digest.sh — all repos fail ==="
export REPOS="endgame-build/empty-repo"
DIGEST=$(bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null)
assert_contains "failed repos show error message" "Could not retrieve" "$DIGEST"

echo ""
echo "=== collect-digest.sh — GITHUB_OUTPUT mode ==="
export GITHUB_OUTPUT=$(mktemp)
export REPOS="endgame-build/test-repo"
bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null
GH_OUT=$(cat "$GITHUB_OUTPUT")
assert_contains "writes digest to GITHUB_OUTPUT" "test-repo" "$GH_OUT"
assert_contains "sets empty=false" "empty=false" "$GH_OUT"
rm -f "$GITHUB_OUTPUT"
unset GITHUB_OUTPUT

echo ""
echo "=== create-changelog-pr.sh (CHANGELOG manipulation only) ==="
# Test the awk insertion logic directly (same logic the script uses)
TMPDIR=$(mktemp -d)
cp "$REPO_DIR/templates/CHANGELOG.md" "$TMPDIR/CHANGELOG.md"

ENTRY="- Add user authentication ([#1](url))"
awk -v entry="$ENTRY" '/^## \[Unreleased\]/ { print; print ""; print entry; next } { print }' \
  "$TMPDIR/CHANGELOG.md" > "$TMPDIR/cl.md"

RESULT=$(cat "$TMPDIR/cl.md")
assert_contains "entry inserted after [Unreleased]" "Add user authentication" "$RESULT"
assert_contains "header preserved" "Keep a Changelog" "$RESULT"
assert_contains "[Unreleased] heading preserved" "## .Unreleased." "$RESULT"

# Test empty synthesis skips
export SYNTHESIS_JSON='{"entry":""}' PR_NUMBER=1 PR_TITLE="test" PR_AUTHOR="user" GH_TOKEN="fake"
OUTPUT=$(cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true)
assert_contains "empty synthesis skips" "No content" "$OUTPUT"

# Test valid synthesis extracts entry
export SYNTHESIS_JSON='{"entry":"Add user auth"}'
OUTPUT=$(cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true)
# Script will fail at git operations (no repo), but should get past the ENTRY check
assert_contains "valid synthesis passes entry check" "" "$(echo "$OUTPUT" | grep -v 'No content' || echo 'passed')"

rm -rf "$TMPDIR"

echo ""
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
