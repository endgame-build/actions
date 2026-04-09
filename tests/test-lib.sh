#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/harness.sh"

echo "=== lib.sh — retry ==="

source "$REPO_DIR/scripts/lib.sh"

echo "-- Happy path: succeeds on first try --"
OUTPUT=$(retry 3 echo "hello" 2>/dev/null)
assert_eq "returns output" "hello" "$OUTPUT"

echo "-- Retry: fails then succeeds --"
COUNTER_FILE=$(mktemp)
echo "0" > "$COUNTER_FILE"
flaky() {
  local count=$(cat "$COUNTER_FILE")
  count=$((count + 1))
  echo "$count" > "$COUNTER_FILE"
  [ "$count" -ge 2 ] && echo "ok" && return 0
  return 1
}
OUTPUT=$(retry 3 flaky 2>/dev/null)
assert_eq "succeeds on second attempt" "ok" "$OUTPUT"
rm -f "$COUNTER_FILE"

echo "-- Exhausted: fails all attempts --"
retry 2 false 2>/dev/null
EXIT=$?
assert_exit_code "returns failure after exhaustion" "1" "$EXIT"

report
