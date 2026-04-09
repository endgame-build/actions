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
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
