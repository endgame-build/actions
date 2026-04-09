#!/usr/bin/env bash
# Run all test suites. Exit 1 if any suite fails.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0 TOTAL_FAIL=0 FAILED_SUITES=""

for suite in "$SCRIPT_DIR"/test-*.sh; do
  echo ""
  bash "$suite"
  EXIT=$?

  # Extract pass/fail counts from last line of output
  if [ $EXIT -ne 0 ]; then
    FAILED_SUITES="$FAILED_SUITES $(basename "$suite")"
  fi
done

echo ""
echo "==============================="
if [ -z "$FAILED_SUITES" ]; then
  echo "All suites passed."
  exit 0
else
  echo "FAILED suites:$FAILED_SUITES"
  exit 1
fi
