#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/harness.sh"

echo "=== measure-instability.sh ==="

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Fixture A: 2 entries, 2 SHAs
cat > "$TMPDIR/a.md" << 'EOF'
# Changelog
## [Unreleased]
### Added
- Add thing ([`abc1234`](url))
- Add other ([#42](url))
EOF

# Fixture B: same 2 SHAs + 1 more = 3 entries
cat > "$TMPDIR/b.md" << 'EOF'
# Changelog
## [Unreleased]
### Added
- Add thing ([`abc1234`](url))
- Add other ([#42](url))
- New one ([`def5678`](url))
EOF

echo "-- Basic 2-file comparison --"
OUT=$(bash "$SCRIPT_DIR/measure-instability.sh" "$TMPDIR/a.md" "$TMPDIR/b.md")
assert_contains "reports entry counts" "Entry counts: 2 3" "$OUT"
assert_contains "computes mean" "Mean: 2.5" "$OUT"
assert_contains "reports SHA intersection" "SHAs in ALL runs (intersection): 1" "$OUT"
assert_contains "reports SHA union" "SHAs in ANY run (union): 2" "$OUT"
assert_contains "reports PR links" "PR links per run: 1 1" "$OUT"

echo "-- 3-file comparison --"
cp "$TMPDIR/a.md" "$TMPDIR/c.md"
OUT=$(bash "$SCRIPT_DIR/measure-instability.sh" "$TMPDIR/a.md" "$TMPDIR/b.md" "$TMPDIR/c.md")
assert_contains "3 entry counts" "Entry counts: 2 3 2" "$OUT"

echo "-- Rejects single file --"
if bash "$SCRIPT_DIR/measure-instability.sh" "$TMPDIR/a.md" 2>/dev/null; then
  echo "  ✗ should reject 1-file input"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ rejects 1-file input"
  PASS=$((PASS + 1))
fi

echo "-- Errors on missing file --"
if bash "$SCRIPT_DIR/measure-instability.sh" "$TMPDIR/a.md" "$TMPDIR/nope.md" 2>/dev/null; then
  echo "  ✗ should error on missing file"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ errors on missing file"
  PASS=$((PASS + 1))
fi

report
