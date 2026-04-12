#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/harness.sh"
source "$REPO_DIR/scripts/lib/classify-lib.sh"

echo "=== classify-commits — lib ==="

echo "-- classify_skip patterns --"
assert_eq "typo fix" "typo" "$(classify_skip 'fix: fix typo in README')"
assert_eq "chore typo" "typo" "$(classify_skip 'chore: typo')"
assert_eq "docs typos" "typo" "$(classify_skip 'docs: typos in API doc')"
assert_eq "merge main" "merge_infra" "$(classify_skip "Merge branch 'main' of github.com:foo/bar")"
assert_eq "auto-generated" "auto_generated" "$(classify_skip 'docs(changelog): update for #42')"
assert_eq "backup" "backup" "$(classify_skip 'bd: backup 2026-03-05')"
assert_eq "comments metadata" "comments_metadata" "$(classify_skip 'Update comments')"
assert_eq "comments lower" "comments_metadata" "$(classify_skip 'update comments')"
assert_eq "real feat not skipped" "" "$(classify_skip 'feat: add user auth')"
assert_eq "real fix not skipped" "" "$(classify_skip 'fix: prevent null deref')"
assert_eq "chore PRD not skipped" "" "$(classify_skip 'chore: add pet registration PRD')"

echo "-- classify_source --"
RES=$(classify_source 'Merge pull request #162 from foo/bar' yes)
assert_eq "merge PR" "B|162" "$RES"
RES=$(classify_source "Merge branch main" yes)
assert_eq "merge no PR" "B|" "$RES"
RES=$(classify_source 'feat: add auth (#42)' no)
assert_eq "squash PR" "A|42" "$RES"
RES=$(classify_source 'feat: refactor' no)
assert_eq "direct" "C|" "$RES"

echo "-- classify_category (conventional prefixes) --"
assert_eq "feat" "Added" "$(classify_category 'feat: x' '' '')"
assert_eq "feat scope" "Added" "$(classify_category 'feat(api): x' '' '')"
assert_eq "fix" "Fixed" "$(classify_category 'fix: x' '' '')"
assert_eq "docs" "Changed" "$(classify_category 'docs: x' '' '')"
assert_eq "chore" "Changed" "$(classify_category 'chore: x' '' '')"
assert_eq "security" "Security" "$(classify_category 'security: fix CVE' '' '')"
assert_eq "deprecate" "Deprecated" "$(classify_category 'deprecate(api): old endpoint' '' '')"

echo "-- classify_category (filter-based) --"
assert_eq "all additions → Added" "Added" "$(classify_category 'Add stuff' '' 'AAA')"
assert_eq "all deletions → Removed" "Removed" "$(classify_category 'Delete stuff' '' 'DD')"

echo "-- classify_category (verb heuristic) --"
assert_eq "remove verb" "Removed" "$(classify_category 'Remove old code' '' 'M')"
assert_eq "add verb" "Added" "$(classify_category 'Add new thing' '' 'M')"
assert_eq "default Changed" "Changed" "$(classify_category 'Refactor internals' '' 'M')"

echo "-- classify_group_key --"
K1=$(classify_group_key 'Update README.md' '2026-04-01')
K2=$(classify_group_key 'Update README.md' '2026-04-01')
assert_eq "same input = same key" "$K1" "$K2"
K3=$(classify_group_key 'Update README.md' '2026-04-02')
if [ "$K1" = "$K3" ]; then
  echo "  ✗ different dates should give different keys"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ different dates give different keys"
  PASS=$((PASS + 1))
fi

echo "-- classify_link_type --"
assert_eq "source A with PR → pr" "pr" "$(classify_link_type 'A' '42')"
assert_eq "source B with PR → pr" "pr" "$(classify_link_type 'B' '162')"
assert_eq "source B no PR → commit" "commit" "$(classify_link_type 'B' '')"
assert_eq "source C → commit" "commit" "$(classify_link_type 'C' '')"

echo ""
echo "=== classify-commits — script ==="

REPO_FIXTURE="/tmp/worktrees/changelog-sandbox-v4"
if [ -d "$REPO_FIXTURE/.git" ]; then
  echo "-- Determinism --"
  bash "$REPO_DIR/scripts/classify-commits.sh" "$REPO_FIXTURE" > /tmp/classify-r1.json
  bash "$REPO_DIR/scripts/classify-commits.sh" "$REPO_FIXTURE" > /tmp/classify-r2.json
  if diff -q /tmp/classify-r1.json /tmp/classify-r2.json > /dev/null; then
    echo "  ✓ two runs are byte-identical"
    PASS=$((PASS + 1))
  else
    echo "  ✗ two runs differ"
    FAIL=$((FAIL + 1))
  fi

  echo "-- Valid JSON --"
  if jq empty /tmp/classify-r1.json 2>/dev/null; then
    echo "  ✓ output is valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  ✗ output is invalid JSON"
    FAIL=$((FAIL + 1))
  fi

  echo "-- Record count --"
  COUNT=$(jq 'length' /tmp/classify-r1.json)
  GIT_COUNT=$(cd "$REPO_FIXTURE" && git log --first-parent --format='%H' main | wc -l | tr -d ' ')
  assert_eq "record count matches git log --first-parent" "$GIT_COUNT" "$COUNT"

  echo "-- Required fields present --"
  for FIELD in sha subject author_date source category group_key skip_reason link_type; do
    PRESENT=$(jq -r ".[0].$FIELD // empty" /tmp/classify-r1.json)
    if [ -n "$PRESENT" ] || [ "$FIELD" = "skip_reason" ]; then
      echo "  ✓ field $FIELD present"
      PASS=$((PASS + 1))
    else
      echo "  ✗ field $FIELD missing"
      FAIL=$((FAIL + 1))
    fi
  done

  rm -f /tmp/classify-r1.json /tmp/classify-r2.json
else
  echo "  (skipped — $REPO_FIXTURE not found)"
fi

echo "-- Errors on bad input --"
if bash "$REPO_DIR/scripts/classify-commits.sh" /tmp/does-not-exist 2>/dev/null; then
  echo "  ✗ should error on missing repo"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ errors on missing repo"
  PASS=$((PASS + 1))
fi

if bash "$REPO_DIR/scripts/classify-commits.sh" 2>/dev/null; then
  echo "  ✗ should error on missing arg"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ errors on missing arg"
  PASS=$((PASS + 1))
fi

report
