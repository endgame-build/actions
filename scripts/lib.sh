#!/usr/bin/env bash
# Shared functions for changelog pipeline scripts.

# Retry a command up to N times with backoff.
# Usage: retry 3 gh api repos/org/repo/contents/file
retry() {
  local max_attempts=$1; shift
  local attempt=1
  while [ $attempt -le "$max_attempts" ]; do
    if "$@"; then
      return 0
    fi
    echo "Attempt $attempt/$max_attempts failed: $*" >&2
    attempt=$((attempt + 1))
    [ $attempt -le "$max_attempts" ] && sleep $((attempt * 2))
  done
  echo "All $max_attempts attempts failed: $*" >&2
  return 1
}
