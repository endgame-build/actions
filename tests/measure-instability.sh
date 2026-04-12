#!/usr/bin/env bash
# Measure instability across multiple CHANGELOG.md runs.
# Usage: measure-instability.sh <file1> <file2> [file3...]
#
# Outputs: entry count per run, unique SHA sets, category distribution,
# intersection of SHAs across all runs, wording stability.
set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <changelog1.md> <changelog2.md> [changelog3.md...]" >&2
  exit 2
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

i=0
for F in "$@"; do
  i=$((i + 1))
  [ -f "$F" ] || { echo "ERROR: $F not found" >&2; exit 1; }
  grep -oE '\[`[a-f0-9]+`\]' "$F" | sort -u > "$TMPDIR/shas-$i.txt"
  grep -oE '\(\[#[0-9]+\]' "$F" | sort -u > "$TMPDIR/prs-$i.txt"
  grep -c '^- ' "$F" > "$TMPDIR/entries-$i.txt" 2>/dev/null || echo 0 > "$TMPDIR/entries-$i.txt"
  awk '/^### / { cat = $2 } /^- / && cat { print cat }' "$F" > "$TMPDIR/cat-$i.txt"
done

N=$i

echo "=== Instability report across $N runs ==="
echo ""

# Entry counts
printf "Entry counts: "
for j in $(seq 1 $N); do
  printf "%s " "$(cat "$TMPDIR/entries-$j.txt")"
done
echo ""

# Mean and stddev
MEAN=$(for j in $(seq 1 $N); do cat "$TMPDIR/entries-$j.txt"; done | awk '{sum+=$1; n++} END {printf "%.1f", sum/n}')
STDDEV=$(for j in $(seq 1 $N); do cat "$TMPDIR/entries-$j.txt"; done | awk -v mean="$MEAN" '{d=$1-mean; sq+=d*d; n++} END {printf "%.1f", (n>1)?sqrt(sq/(n-1)):0}')
echo "  Mean: $MEAN  Stddev: $STDDEV"
echo ""

# PR links (should be stable)
printf "PR links per run: "
for j in $(seq 1 $N); do
  printf "%s " "$(wc -l < "$TMPDIR/prs-$j.txt" | tr -d ' ')"
done
echo ""

# Unique SHAs per run
printf "Unique SHAs per run: "
for j in $(seq 1 $N); do
  printf "%s " "$(wc -l < "$TMPDIR/shas-$j.txt" | tr -d ' ')"
done
echo ""

# SHA intersection across all runs
cp "$TMPDIR/shas-1.txt" "$TMPDIR/common.txt"
for j in $(seq 2 $N); do
  comm -12 "$TMPDIR/common.txt" "$TMPDIR/shas-$j.txt" > "$TMPDIR/common-next.txt"
  mv "$TMPDIR/common-next.txt" "$TMPDIR/common.txt"
done
COMMON=$(wc -l < "$TMPDIR/common.txt" | tr -d ' ')
echo "  SHAs in ALL runs (intersection): $COMMON"

# SHA union
cat "$TMPDIR/shas-"*.txt | sort -u > "$TMPDIR/union.txt"
UNION=$(wc -l < "$TMPDIR/union.txt" | tr -d ' ')
echo "  SHAs in ANY run (union): $UNION"

# Stability ratio
if [ "$UNION" -gt 0 ]; then
  RATIO=$((COMMON * 100 / UNION))
  echo "  Stability ratio (common/union): $RATIO%"
fi
echo ""

# Category distribution
echo "Category distribution per run:"
for j in $(seq 1 $N); do
  printf "  Run %s: " "$j"
  sort "$TMPDIR/cat-$j.txt" | uniq -c | awk '{printf "%s=%s ", $2, $1}'
  echo ""
done
