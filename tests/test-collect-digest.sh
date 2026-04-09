#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/harness.sh"

export PATH="$SCRIPT_DIR/mocks:$PATH"
export GH_TOKEN=fake

echo "=== collect-digest.sh ==="

echo "-- Happy path: repo with unreleased entries --"
unset GITHUB_OUTPUT 2>/dev/null || true
export REPOS="endgame-build/test-repo"
DIGEST=$(bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null)
assert_contains "includes repo name in bold" "test-repo" "$DIGEST"
assert_contains "includes Added entries" "Add user authentication" "$DIGEST"
assert_contains "includes Fixed entries" "Fix login redirect" "$DIGEST"
assert_not_contains "excludes release section" "1.0.0" "$DIGEST"

echo "-- Happy path: multiple repos --"
export REPOS="endgame-build/test-repo endgame-build/test-repo"
DIGEST=$(bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null)
COUNT=$(echo "$DIGEST" | grep -c "test-repo" || true)
assert_eq "shows each repo separately" "2" "$COUNT"

echo "-- Edge case: repo returns 404 --"
export REPOS="endgame-build/empty-repo"
DIGEST=$(bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null)
assert_contains "shows error for failed repo" "Could not retrieve" "$DIGEST"

echo "-- Edge case: mix of working and failed repos --"
export REPOS="endgame-build/test-repo endgame-build/empty-repo"
DIGEST=$(bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null)
assert_contains "includes working repo" "Add user authentication" "$DIGEST"
assert_contains "includes failed repo error" "Could not retrieve" "$DIGEST"

echo "-- Edge case: empty REPOS --"
export REPOS=""
DIGEST=$(bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null)
assert_empty "empty REPOS produces empty digest" "$DIGEST"

echo "-- GITHUB_OUTPUT mode: writes step outputs --"
export GITHUB_OUTPUT=$(mktemp)
export REPOS="endgame-build/test-repo"
bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null
OUT=$(cat "$GITHUB_OUTPUT")
assert_contains "writes digest heredoc" "digest<<DIGEST_EOF" "$OUT"
assert_contains "sets empty=false for non-empty" "empty=false" "$OUT"
assert_contains "digest content in output" "test-repo" "$OUT"
rm -f "$GITHUB_OUTPUT"

echo "-- GITHUB_OUTPUT mode: empty digest --"
export GITHUB_OUTPUT=$(mktemp)
export REPOS="endgame-build/empty-repo"
bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null
OUT=$(cat "$GITHUB_OUTPUT")
assert_contains "sets empty=true for error-only" "empty=false" "$OUT"
rm -f "$GITHUB_OUTPUT"
unset GITHUB_OUTPUT

echo "-- Format: output uses Slack mrkdwn --"
export REPOS="endgame-build/test-repo"
DIGEST=$(bash "$REPO_DIR/scripts/collect-digest.sh" 2>/dev/null)
assert_contains "repo name is bold" '*test-repo*' "$DIGEST"
assert_contains "entries are plain text" "Add user" "$DIGEST"

report
