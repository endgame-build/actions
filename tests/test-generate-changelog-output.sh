#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/harness.sh"

echo "=== generate-changelog output validation ==="

# --- Tests against known-good changelog ---
GOOD="$SCRIPT_DIR/fixtures/changelog-good.md"

echo "-- Structure: keepachangelog format --"
assert_contains "has Changelog header" "# Changelog" "$(cat "$GOOD")"
assert_contains "has [Unreleased] section" "## [Unreleased]" "$(cat "$GOOD")"
assert_contains "has Keep a Changelog link" "keepachangelog.com" "$(cat "$GOOD")"

echo "-- PR links present for merge-commit entries --"
PR_LINK_COUNT=$(grep -cE '\(\[#[0-9]+\]\(https://' "$GOOD" || true)
assert_eq "good changelog has PR links" "true" "$([ "$PR_LINK_COUNT" -gt 0 ] && echo true || echo false)"

echo "-- Commit links present for direct-push entries --"
COMMIT_LINK_COUNT=$(grep -cE '\(\[`[a-f0-9]+`\]\(https://' "$GOOD" || true)
assert_eq "good changelog has commit links" "true" "$([ "$COMMIT_LINK_COUNT" -gt 0 ] && echo true || echo false)"

echo "-- Multi-SHA grouped entries supported --"
# A grouped entry lists multiple SHAs separated by ", ". Example: ([`sha1`](url), [`sha2`](url))
MULTI_SHA_LINE=$(grep -E '\[`[a-f0-9]+`\]\([^)]+\), \[`[a-f0-9]+`\]' "$GOOD" | head -1)
assert_not_empty "good changelog has at least one multi-SHA grouped entry" "$MULTI_SHA_LINE"

echo "-- Category ordering --"
CL="$(cat "$GOOD")"
ADDED_LINE=$(echo "$CL" | grep -n '### Added' | head -1 | cut -d: -f1)
CHANGED_LINE=$(echo "$CL" | grep -n '### Changed' | head -1 | cut -d: -f1)
REMOVED_LINE=$(echo "$CL" | grep -n '### Removed' | head -1 | cut -d: -f1)
FIXED_LINE=$(echo "$CL" | grep -n '### Fixed' | head -1 | cut -d: -f1)
assert_eq "Added before Changed" "true" "$([ "$ADDED_LINE" -lt "$CHANGED_LINE" ] && echo true || echo false)"
assert_eq "Changed before Removed" "true" "$([ "$CHANGED_LINE" -lt "$REMOVED_LINE" ] && echo true || echo false)"
assert_eq "Removed before Fixed" "true" "$([ "$REMOVED_LINE" -lt "$FIXED_LINE" ] && echo true || echo false)"

# --- Tests against known-bad changelog ---
BAD="$SCRIPT_DIR/fixtures/changelog-bad-no-prs.md"

echo "-- Detect missing PR links --"
BAD_PR_COUNT=$(grep -cE '\(\[#[0-9]+\]\(https://' "$BAD" || true)
assert_eq "bad changelog has zero PR links" "0" "$BAD_PR_COUNT"

echo "-- Detect noise entries --"
assert_contains "bad changelog has typo noise" "Fix typos" "$(cat "$BAD")"
assert_contains "bad changelog has formatting noise" "Refine README formatting" "$(cat "$BAD")"
assert_contains "bad changelog has version bump noise" "Bump endgame plugin version" "$(cat "$BAD")"

# --- Validation function for any CHANGELOG.md ---
# Pass the file path as first argument to this script.
if [ -n "${1:-}" ] && [ -f "$1" ]; then
  echo ""
  echo "-- Validating: $1 --"
  CL="$(cat "$1")"

  echo "-- Structure checks --"
  assert_contains "has Changelog header" "# Changelog" "$CL"
  assert_contains "has [Unreleased] section" "## [Unreleased]" "$CL"

  echo "-- PR link checks --"
  ENTRY_COUNT=$(grep -c '^- ' "$1" || true)
  PR_LINK_COUNT=$(grep -cE '\(\[#[0-9]+\]\(https://' "$1" || true)
  COMMIT_LINK_COUNT=$(grep -cE '\(\[`[a-f0-9]+`\]\(https://' "$1" || true)
  TOTAL_LINKS=$((PR_LINK_COUNT + COMMIT_LINK_COUNT))
  echo "    Entries: $ENTRY_COUNT  PR links: $PR_LINK_COUNT  Commit links: $COMMIT_LINK_COUNT"
  assert_eq "every entry has a link" "$ENTRY_COUNT" "$TOTAL_LINKS"
  assert_eq "at least some PR links exist" "true" "$([ "$PR_LINK_COUNT" -gt 0 ] && echo true || echo false)"

  echo "-- Noise checks --"
  assert_not_contains "no typo entries" "Fix typos" "$CL"
  assert_not_contains "no 'Update README.md' raw entries" "Update README.md" "$CL"
  assert_not_contains "no 'Refine README' raw entries" "Refine README formatting" "$CL"
  assert_not_contains "no bare version bumps" "Bump endgame plugin version" "$CL"
  assert_not_contains "no 'Merge branch' entries" "Merge branch" "$CL"

  echo "-- Category checks --"
  assert_contains "has Added section" "### Added" "$CL"
  HAS_ADDED=$(echo "$CL" | grep -c '### Added' || true)
  assert_eq "exactly one Added section" "1" "$HAS_ADDED"

  echo "-- Concreteness: entries start with action verbs --"
  CONCRETE_COUNT=$(grep -cE '^- (Add|Fix|Remove|Rename|Move|Replace|Improve|Enable|Disable|Merge|Split|Consolidate|Refactor|Convert|Switch|Upgrade|Update|Introduce|Document|Expose|Deprecate|Restore|Mark|Rewrite|Reconcile|Extract|Bump|Initialize|Align|Address) ' "$1" || true)
  if [ "$ENTRY_COUNT" -gt 0 ]; then
    PCT=$((CONCRETE_COUNT * 100 / ENTRY_COUNT))
    echo "    Concrete: $CONCRETE_COUNT / $ENTRY_COUNT ($PCT%)"
    assert_eq "concreteness >= 80%" "true" "$([ "$PCT" -ge 80 ] && echo true || echo false)"
  fi

  # --- Regression fixture: required SHAs present, forbidden subjects absent ---
  # Usage: pass repo key as 2nd arg, e.g. "endgame-build/odevo-hub"
  if [ -n "${2:-}" ] && [ -f "$SCRIPT_DIR/fixtures/required-entries.json" ]; then
    echo "-- Regression fixture: $2 --"
    REQUIRED=$(jq -r --arg repo "$2" '.per_repo[$repo].required_shas[]?' "$SCRIPT_DIR/fixtures/required-entries.json" 2>/dev/null || true)
    for SHA in $REQUIRED; do
      assert_contains "required SHA $SHA present" "$SHA" "$CL"
    done
    FORBIDDEN=$(jq -r --arg repo "$2" '.per_repo[$repo].forbidden_subjects[]?' "$SCRIPT_DIR/fixtures/required-entries.json" 2>/dev/null || true)
    while IFS= read -r SUBJ; do
      [ -z "$SUBJ" ] && continue
      assert_not_contains "forbidden subject absent: $SUBJ" "$SUBJ" "$CL"
    done <<< "$FORBIDDEN"
  fi

  # --- Coverage honesty: commits referenced / total direct commits ---
  # Usage: pass repo clone path as 3rd arg
  if [ -n "${3:-}" ] && [ -d "$3/.git" ]; then
    echo "-- Coverage honesty --"
    TOTAL_DIRECT=$(cd "$3" && git log --first-parent --no-merges --format="%h" main 2>/dev/null | wc -l | tr -d ' ')
    UNIQUE_COMMIT_SHAS=$(grep -oE '\[`[a-f0-9]+`\]' "$1" | sort -u | wc -l | tr -d ' ')
    if [ "$TOTAL_DIRECT" -gt 50 ]; then
      PCT=$((UNIQUE_COMMIT_SHAS * 100 / TOTAL_DIRECT))
      echo "    Direct commits: $TOTAL_DIRECT  referenced: $UNIQUE_COMMIT_SHAS ($PCT%)"
      if [ "$PCT" -lt 40 ]; then
        echo "    WARNING: coverage $PCT% is below 40% threshold"
      fi
    fi
  fi
fi

report
