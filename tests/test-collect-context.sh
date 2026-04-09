#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/harness.sh"

export PATH="$SCRIPT_DIR/mocks:$PATH"
export GH_TOKEN=fake PR_NUMBER=42

echo "=== collect-context.sh ==="

echo "-- Happy path: PR with changes --"
export GITHUB_OUTPUT=$(mktemp)
bash "$REPO_DIR/scripts/collect-context.sh"
OUT=$(cat "$GITHUB_OUTPUT")
assert_contains "sets changed=true" "changed=true" "$OUT"
assert_contains "cliff output uses heredoc format" "cliff<<EOF_cliff" "$OUT"
assert_contains "desc output uses heredoc format" "desc<<EOF_desc" "$OUT"
assert_contains "diff output uses heredoc format" "diff<<EOF_diff" "$OUT"
assert_contains "commits output uses heredoc format" "commits<<EOF_commits" "$OUT"
assert_contains "cliff includes changelog diff content" "Add user authentication" "$OUT"
assert_contains "desc includes PR body" "OAuth2" "$OUT"
assert_contains "diff includes file stats" "src/auth.ts" "$OUT"
assert_contains "diff includes file names" "src/login.ts" "$OUT"
assert_contains "commits includes messages" "session management" "$OUT"
rm -f "$GITHUB_OUTPUT"

echo "-- Edge case: no changes in CHANGELOG.md --"
# Override git mock to make diff --quiet succeed (exit 0)
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/git" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *"diff --quiet"*) exit 0 ;;  # no changes
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_DIR/git"
export GITHUB_OUTPUT=$(mktemp)
PATH="$MOCK_DIR:$SCRIPT_DIR/mocks:$PATH" bash "$REPO_DIR/scripts/collect-context.sh"
OUT=$(cat "$GITHUB_OUTPUT")
assert_contains "sets changed=false when no diff" "changed=false" "$OUT"
assert_not_contains "no cliff output when unchanged" "cliff<<" "$OUT"
assert_not_contains "no desc output when unchanged" "desc<<" "$OUT"
rm -f "$GITHUB_OUTPUT" "$MOCK_DIR/git"
rmdir "$MOCK_DIR"

echo "-- Edge case: gh pr view fails --"
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
exit 1  # all gh commands fail
EOF
chmod +x "$MOCK_DIR/gh"
export GITHUB_OUTPUT=$(mktemp)
PATH="$MOCK_DIR:$SCRIPT_DIR/mocks:$PATH" bash "$REPO_DIR/scripts/collect-context.sh" 2>/dev/null
OUT=$(cat "$GITHUB_OUTPUT")
assert_contains "still sets changed=true" "changed=true" "$OUT"
assert_contains "desc falls back gracefully" "desc<<EOF_desc" "$OUT"
assert_contains "commits falls back gracefully" "commits<<EOF_commits" "$OUT"
rm -f "$GITHUB_OUTPUT" "$MOCK_DIR/gh"
rmdir "$MOCK_DIR"

echo "-- Format: heredoc delimiters are unique --"
export GITHUB_OUTPUT=$(mktemp)
bash "$REPO_DIR/scripts/collect-context.sh"
OUT=$(cat "$GITHUB_OUTPUT")
assert_eq "cliff delimiter count" "2" "$(grep -c "EOF_cliff" <<< "$OUT")"
assert_eq "desc delimiter count" "2" "$(grep -c "EOF_desc" <<< "$OUT")"
assert_eq "diff delimiter count" "2" "$(grep -c "EOF_diff" <<< "$OUT")"
assert_eq "commits delimiter count" "2" "$(grep -c "EOF_commits" <<< "$OUT")"
rm -f "$GITHUB_OUTPUT"

echo "-- Edge case: 2MB diff triggers truncation warning --"
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/git" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *"diff --quiet"*) exit 1 ;;
  "diff CHANGELOG.md")
    # Generate 2MB of output
    python3 -c "print('+ added line ' * 100000)" 2>/dev/null || \
    perl -e 'print "+ added line \n" x 100000' 2>/dev/null || \
    yes "+ added line" | head -100000
    ;;
  *"diff --stat"*) echo "big.txt | 100000 ++" ;;
  *"diff --name-only"*) echo "big.txt" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_DIR/git"
export GITHUB_OUTPUT=$(mktemp)
STDERR=$(PATH="$MOCK_DIR:$SCRIPT_DIR/mocks:$PATH" bash "$REPO_DIR/scripts/collect-context.sh" 2>&1 >/dev/null)
assert_contains "warns about truncation" "WARNING" "$STDERR"
assert_contains "warning names the field" "cliff" "$STDERR"
OUT=$(cat "$GITHUB_OUTPUT")
# Verify output exists but is capped
assert_contains "truncated output still has heredoc" "cliff<<EOF_cliff" "$OUT"
CLIFF_SIZE=$(sed -n '/^cliff<<EOF_cliff$/,/^EOF_cliff$/p' "$GITHUB_OUTPUT" | wc -c)
# Should be around 50KB, not 2MB
assert_eq "output is capped (under 250KB)" "true" "$([ "$CLIFF_SIZE" -lt 250000 ] && echo true || echo false)"
rm -f "$GITHUB_OUTPUT" "$MOCK_DIR/git"
rmdir "$MOCK_DIR"

report
