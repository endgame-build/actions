#!/usr/bin/env bash
# Deterministic commit classifier for /generate-changelog.
# Phase A: emit JSON records with sha/category/group_key/skip_reason per commit.
# Phase B (agent): polishes wording using this classification.
#
# Usage: classify-commits.sh <repo-clone-path>
# Output: JSON array on stdout, sorted by author_date descending.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <repo-clone-path>" >&2
  exit 2
fi

REPO="$1"
[ -d "$REPO/.git" ] || { echo "ERROR: $REPO is not a git repo" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/classify-lib.sh
source "$SCRIPT_DIR/lib/classify-lib.sh"

# Stream commits in a format we can parse unambiguously.
# Use NUL-separated records to handle multi-line subjects safely.
DEFAULT_BRANCH=$(cd "$REPO" && git symbolic-ref --short HEAD 2>/dev/null || echo "main")

cd "$REPO"

printf '['
FIRST=1

# First-parent log gives us main-line history (merges + direct commits).
# Format: sha|parents|author_date|subject
while IFS='|' read -r sha parents date subject; do
  [ -z "$sha" ] && continue

  # Is this a merge commit? (more than one parent)
  is_merge="no"
  parent_count=$(echo "$parents" | wc -w | tr -d ' ')
  [ "$parent_count" -gt 1 ] && is_merge="yes"

  # Classify source
  source_pr=$(classify_source "$subject" "$is_merge")
  source="${source_pr%|*}"
  pr_number="${source_pr#*|}"

  # Classify skip reason (noise patterns)
  skip_reason=""
  if [ "$is_merge" = "yes" ] && [ -z "$pr_number" ]; then
    # Merge branch of main etc — infrastructure
    skip_reason="merge_infra"
  else
    skip_reason=$(classify_skip "$subject")
  fi

  # Get files changed for category classification (only if not skipped)
  files_changed=0
  filters=""
  category="Changed"
  if [ -z "$skip_reason" ]; then
    filters=$(git diff-tree --no-commit-id --name-status -r "$sha" 2>/dev/null | awk '{print $1}' | tr -d '\n' || echo "")
    files_changed=$(echo -n "$filters" | wc -c | tr -d ' ')
    category=$(classify_category "$subject" "" "$filters")
  fi

  # Group key
  iso_date=$(echo "$date" | cut -c1-10)
  group_key=$(classify_group_key "$subject" "$iso_date")

  # Link type
  link_type=$(classify_link_type "$source" "$pr_number")

  # Emit JSON record
  [ $FIRST -eq 1 ] && FIRST=0 || printf ','
  printf '\n  {'
  printf '"sha":"%s",' "$sha"
  printf '"subject":%s,' "$(printf '%s' "$subject" | jq -Rs .)"
  printf '"author_date":"%s",' "$date"
  printf '"source":"%s",' "$source"
  if [ -n "$pr_number" ]; then
    printf '"pr_number":%s,' "$pr_number"
  else
    printf '"pr_number":null,'
  fi
  printf '"category":"%s",' "$category"
  printf '"group_key":"%s",' "$group_key"
  if [ -n "$skip_reason" ]; then
    printf '"skip_reason":"%s",' "$skip_reason"
  else
    printf '"skip_reason":null,'
  fi
  printf '"files_changed":%s,' "$files_changed"
  printf '"link_type":"%s"' "$link_type"
  printf '}'
done < <(git log --first-parent --format='%H|%P|%aI|%s' "$DEFAULT_BRANCH")

printf '\n]\n'
