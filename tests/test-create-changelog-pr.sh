#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/harness.sh"

# Mock git/gh to prevent real operations
export PATH="$SCRIPT_DIR/mocks:$PATH"
export GH_TOKEN=fake PR_NUMBER=42 PR_TITLE="feat: add auth" PR_AUTHOR="adkozlov"

echo "=== create-changelog-pr.sh ==="

echo "-- ENTRY extraction from SYNTHESIS_JSON --"
export SYNTHESIS_JSON='{"entry":"Add OAuth2 authentication support"}'
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.actions/templates"
cp "$REPO_DIR/templates/CHANGELOG.md" "$TMPDIR/.actions/templates/CHANGELOG.md"
OUTPUT=$(cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true)
assert_not_contains "does not skip with valid entry" "No content" "$OUTPUT"
assert_contains "CHANGELOG.md has entry" "OAuth2 authentication" "$(cat "$TMPDIR/CHANGELOG.md" 2>/dev/null || echo '')"
rm -rf "$TMPDIR"

echo "-- Empty synthesis skips --"
export SYNTHESIS_JSON='{"entry":""}'
TMPDIR=$(mktemp -d)
OUTPUT=$(cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true)
assert_contains "empty entry outputs skip message" "No content" "$OUTPUT"
rm -rf "$TMPDIR"

echo "-- Null entry skips --"
export SYNTHESIS_JSON='{}'
TMPDIR=$(mktemp -d)
OUTPUT=$(cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true)
assert_contains "missing entry key skips" "No content" "$OUTPUT"
rm -rf "$TMPDIR"

echo "-- CHANGELOG.md bootstrap from template --"
export SYNTHESIS_JSON='{"entry":"Test entry"}'
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.actions/templates"
cp "$REPO_DIR/templates/CHANGELOG.md" "$TMPDIR/.actions/templates/CHANGELOG.md"
# No CHANGELOG.md exists — script should create it from template
cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true
assert_contains "creates CHANGELOG.md from template" "Keep a Changelog" "$(cat "$TMPDIR/CHANGELOG.md" 2>/dev/null || echo '')"
assert_contains "new file has [Unreleased]" "Unreleased" "$(cat "$TMPDIR/CHANGELOG.md" 2>/dev/null || echo '')"
assert_contains "entry is inserted" "Test entry" "$(cat "$TMPDIR/CHANGELOG.md" 2>/dev/null || echo '')"
rm -rf "$TMPDIR"

echo "-- Existing CHANGELOG.md without [Unreleased] --"
export SYNTHESIS_JSON='{"entry":"New feature"}'
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.actions/templates"
cp "$REPO_DIR/templates/CHANGELOG.md" "$TMPDIR/.actions/templates/CHANGELOG.md"
echo -e "# Changelog\n\n## [1.0.0] - 2026-01-01\n- Old entry" > "$TMPDIR/CHANGELOG.md"
cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true
CL=$(cat "$TMPDIR/CHANGELOG.md" 2>/dev/null || echo '')
assert_contains "adds [Unreleased] section" "Unreleased" "$CL"
assert_contains "preserves old content" "Old entry" "$CL"
assert_contains "inserts new entry" "New feature" "$CL"
rm -rf "$TMPDIR"

echo "-- Existing CHANGELOG.md with [Unreleased] --"
export SYNTHESIS_JSON='{"entry":"Second feature"}'
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.actions/templates"
cp "$REPO_DIR/templates/CHANGELOG.md" "$TMPDIR/.actions/templates/CHANGELOG.md"
cat > "$TMPDIR/CHANGELOG.md" << 'CL'
# Changelog

## [Unreleased]

### Added

- First feature

## [1.0.0] - 2026-01-01
CL
cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true
CL=$(cat "$TMPDIR/CHANGELOG.md" 2>/dev/null || echo '')
assert_contains "inserts after [Unreleased]" "Second feature" "$CL"
assert_contains "preserves existing entries" "First feature" "$CL"
assert_contains "preserves release section" "1.0.0" "$CL"
rm -rf "$TMPDIR"

echo "-- Entry with special characters --"
export SYNTHESIS_JSON='{"entry":"Fix `claude-code-action` output parsing ([#42](url))"}'
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.actions/templates"
cp "$REPO_DIR/templates/CHANGELOG.md" "$TMPDIR/.actions/templates/CHANGELOG.md"
cd "$TMPDIR" && bash "$REPO_DIR/scripts/create-changelog-pr.sh" 2>&1 || true
CL=$(cat "$TMPDIR/CHANGELOG.md" 2>/dev/null || echo '')
assert_contains "handles backticks in entry" "claude-code-action" "$CL"
rm -rf "$TMPDIR"

report
