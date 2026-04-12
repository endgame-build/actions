#!/usr/bin/env bash
# Shared classification functions for changelog commit classifier.
# Sourced by scripts/classify-commits.sh and tests.

# Fallback noise patterns used when no external config is present.
# Order matters: first match wins. Keyed by skip_reason name.
_noise_patterns() {
  cat <<'EOF'
typo|^(fix|chore|docs)(\([^)]*\))?: ?(fix )?typos?
formatting|^(fix|chore|docs)(\([^)]*\))?: ?(fix |update )?(white ?space|formatting|indent)
version_bump|^chore: ?bump (version|deps)
merge_infra|^Merge branch '[^']+' of
merge_infra|^Merge remote-tracking branch
auto_generated|^docs(\(changelog\))?: ?update for #[0-9]+
ci_noise|^chore(\(ci\))?: ?(update|bump|pin) (badge|workflow|action)
backup|^(bd:|wip:|scratch:)
comments_metadata|^[Uu]pdate comments?$
todo_notes|^[Uu]pdate (TODO|NOTES)$
EOF
}

# Classify a commit subject against noise patterns.
# Args: subject
# Echoes skip_reason or empty if no match.
classify_skip() {
  local subject="$1"
  while IFS='|' read -r reason pattern; do
    [ -z "$reason" ] && continue
    if echo "$subject" | grep -qiE "$pattern"; then
      echo "$reason"
      return 0
    fi
  done < <(_noise_patterns)
  echo ""
}

# Classify a commit into a changelog category.
# Args: subject, files_changed (newline-separated paths), diff_filter (A/M/D summary)
# Echoes: Added|Changed|Deprecated|Removed|Fixed|Security
classify_category() {
  local subject="$1"
  local files="${2:-}"
  local filters="${3:-}"

  # Conventional prefix first
  case "$subject" in
    feat:*|feat\(*) echo "Added"; return ;;
    fix:*|fix\(*) echo "Fixed"; return ;;
    security:*|security\(*) echo "Security"; return ;;
    deprecate:*|deprecate\(*) echo "Deprecated"; return ;;
    revert:*|revert\(*) echo "Changed"; return ;;
    docs:*|docs\(*|refactor:*|refactor\(*|perf:*|perf\(*|style:*|style\(*|chore:*|chore\(*) echo "Changed"; return ;;
  esac

  # No conventional prefix: use diff filter
  # filters is a string like "A A M" (one char per file)
  if [ -n "$filters" ]; then
    # Only additions: new files = Added
    if echo "$filters" | grep -qE '^A+$'; then
      echo "Added"
      return
    fi
    # Only deletions = Removed
    if echo "$filters" | grep -qE '^D+$'; then
      echo "Removed"
      return
    fi
  fi

  # Subject-verb heuristic
  case "$subject" in
    [Rr]emove*|[Dd]elete*|[Dd]rop*) echo "Removed"; return ;;
    [Aa]dd*|[Cc]reate*|[Ii]ntroduce*) echo "Added"; return ;;
  esac

  # Default
  echo "Changed"
}

# Compute a deterministic group_key for a commit.
# Args: subject, iso_date (YYYY-MM-DD)
# Echoes: lowercase alphanumeric+underscore prefix (25 chars) + date
classify_group_key() {
  local subject="$1"
  local date="$2"
  # Take first 25 chars, lowercase, replace non-alphanumeric with underscore
  local prefix
  prefix=$(echo "$subject" | head -c 25 | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_' | sed 's/_$//')
  printf '%s__%s\n' "$prefix" "$date"
}

# Classify a commit's source.
# Args: subject (full), merge_flag ("yes" or "no")
# Echoes: A|B|C and pr_number (pipe-separated)
classify_source() {
  local subject="$1"
  local is_merge="$2"

  if [ "$is_merge" = "yes" ]; then
    # Merge commit: "Merge pull request #N from ..."
    local pr
    pr=$(echo "$subject" | grep -oE 'Merge pull request #[0-9]+' | grep -oE '[0-9]+' | head -1)
    if [ -n "$pr" ]; then
      echo "B|$pr"
    else
      echo "B|"
    fi
    return
  fi

  # Non-merge: check for squash-merge suffix (#N)
  local pr
  pr=$(echo "$subject" | grep -oE '\(#[0-9]+\)[[:space:]]*$' | grep -oE '[0-9]+')
  if [ -n "$pr" ]; then
    echo "A|$pr"
  else
    echo "C|"
  fi
}

# Classify link type from source + pr_number.
classify_link_type() {
  local source="$1"
  local pr="$2"
  if [ "$source" = "A" ] || [ "$source" = "B" ]; then
    if [ -n "$pr" ]; then
      echo "pr"
      return
    fi
  fi
  echo "commit"
}
