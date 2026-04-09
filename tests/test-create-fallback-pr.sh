#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/harness.sh"

export PATH="$SCRIPT_DIR/mocks:$PATH"
export GH_TOKEN=fake PR_NUMBER=42 PR_TITLE="feat: add auth" PR_AUTHOR="adkozlov"

echo "=== create-fallback-pr.sh ==="

echo "-- No changes: exits cleanly --"
# Mock git diff --quiet to return 0 (no changes)
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/git" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *"diff --quiet"*) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_DIR/git"
OUTPUT=$(PATH="$MOCK_DIR:$PATH" bash "$REPO_DIR/scripts/create-fallback-pr.sh" 2>&1)
EXIT=$?
assert_exit_code "exits 0 when no changes" "0" "$EXIT"
assert_contains "prints no changes message" "No changes" "$OUTPUT"
rm -f "$MOCK_DIR/git"
rmdir "$MOCK_DIR"

echo "-- Has changes: attempts PR creation --"
# Mock git diff --quiet to return 1 (has changes), other git commands succeed
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/git" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
  *"diff --quiet"*) exit 1 ;;  # has changes
  *"push origin --delete"*) exit 0 ;;
  *"config"*) exit 0 ;;
  *"checkout"*) exit 0 ;;
  *"add"*) exit 0 ;;
  *"commit"*) exit 0 ;;
  *"push"*) exit 0 ;;
  *) echo "mock-git: $*" >&2; exit 0 ;;
esac
MOCK
cat > "$MOCK_DIR/gh" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
  *"pr create"*)
    echo "https://github.com/test/pr/1"
    exit 0
    ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK_DIR/git" "$MOCK_DIR/gh"
OUTPUT=$(PATH="$MOCK_DIR:$PATH" bash "$REPO_DIR/scripts/create-fallback-pr.sh" 2>&1)
EXIT=$?
assert_exit_code "exits 0 on success" "0" "$EXIT"
assert_not_contains "does not print no-changes" "No changes" "$OUTPUT"
rm -f "$MOCK_DIR/git" "$MOCK_DIR/gh"
rmdir "$MOCK_DIR"

echo "-- Branch name includes PR number --"
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/git" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
  *"diff --quiet"*) exit 1 ;;
  *"checkout -b changelog/pr-42"*) echo "BRANCH_OK"; exit 0 ;;
  *"push -u origin changelog/pr-42"*) echo "PUSH_OK"; exit 0 ;;
  *) exit 0 ;;
esac
MOCK
cat > "$MOCK_DIR/gh" << 'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$MOCK_DIR/git" "$MOCK_DIR/gh"
OUTPUT=$(PATH="$MOCK_DIR:$PATH" bash "$REPO_DIR/scripts/create-fallback-pr.sh" 2>&1)
assert_contains "creates branch with PR number" "BRANCH_OK" "$OUTPUT"
assert_contains "pushes branch with PR number" "PUSH_OK" "$OUTPUT"
rm -f "$MOCK_DIR/git" "$MOCK_DIR/gh"
rmdir "$MOCK_DIR"

echo "-- Commit message includes [skip ci] --"
MOCK_DIR=$(mktemp -d)
COMMIT_MSG=""
cat > "$MOCK_DIR/git" << 'MOCK'
#!/usr/bin/env bash
case "$*" in
  *"diff --quiet"*) exit 1 ;;
  *"commit -m"*)
    echo "$*" > /tmp/test-commit-msg.txt
    exit 0
    ;;
  *) exit 0 ;;
esac
MOCK
cat > "$MOCK_DIR/gh" << 'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$MOCK_DIR/git" "$MOCK_DIR/gh"
PATH="$MOCK_DIR:$PATH" bash "$REPO_DIR/scripts/create-fallback-pr.sh" 2>&1 || true
COMMIT_MSG=$(cat /tmp/test-commit-msg.txt 2>/dev/null || echo '')
assert_contains "commit message has [skip ci]" "skip ci" "$COMMIT_MSG"
assert_contains "commit message has PR number" "#42" "$COMMIT_MSG"
rm -f "$MOCK_DIR/git" "$MOCK_DIR/gh" /tmp/test-commit-msg.txt
rmdir "$MOCK_DIR"

report
