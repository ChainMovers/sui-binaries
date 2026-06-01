#!/usr/bin/env bash
#
# strip-sui-tarball.sh
#
# Produce a slimmed ("min") variant of an official MystenLabs Sui release
# tarball by REMOVING the binaries that are large and/or unused by typical
# Suibase users. Nothing is rebuilt — the kept binaries are byte-identical
# to upstream; we only drop archive members and re-compress.
#
# Removed binaries (and their *.exe variants on Windows):
#   - sui-debug       (~3.3 GB uncompressed; debug-symbol build of `sui`)
#   - sui-fork        (experimental mainnet-fork dev tool)
#   - sui-bridge      (Sui<->Eth bridge validator daemon)
#   - sui-bridge-cli  (bridge operator/governance CLI)
#
# Usage:
#   strip-sui-tarball.sh <input.tgz> <output.tgz>
#
# Exits non-zero if extraction fails, if any binary that must be kept is
# missing, or if any binary that must be removed survived.

set -euo pipefail

INPUT="${1:?usage: strip-sui-tarball.sh <input.tgz> <output.tgz>}"
OUTPUT="${2:?usage: strip-sui-tarball.sh <input.tgz> <output.tgz>}"

# Binaries to drop. Patterns are matched anywhere in the archived path and
# cover both the bare name and the Windows *.exe variant. Note that
# "*sui-bridge*" intentionally matches both sui-bridge and sui-bridge-cli.
REMOVE_PATTERNS=(
  '*sui-debug*'
  '*sui-fork*'
  '*sui-bridge*'
)

# Binaries that MUST survive the strip (sanity guard against an upstream
# layout change silently producing an empty/broken package).
EXPECT_KEEP=(sui sui-node sui-faucet sui-tool)

# Binaries that MUST be gone afterwards.
EXPECT_GONE=(sui-debug sui-fork sui-bridge sui-bridge-cli)

if [[ ! -f "$INPUT" ]]; then
  echo "ERROR: input tarball not found: $INPUT" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

EXTRACT_DIR="$WORKDIR/extract"
mkdir -p "$EXTRACT_DIR"

echo "==> Input:  $INPUT ($(du -h "$INPUT" | cut -f1))"
echo "==> Output: $OUTPUT"
echo "==> Extracting (excluding removed binaries so they never touch disk)..."

# GNU tar --exclude during extraction skips matching members entirely, so the
# huge sui-debug is never written — saving ~3.3 GB of disk and write I/O.
exclude_args=()
for pat in "${REMOVE_PATTERNS[@]}"; do
  exclude_args+=(--exclude="$pat")
done
tar -x -z -f "$INPUT" -C "$EXTRACT_DIR" "${exclude_args[@]}"

echo "==> Kept files:"
( cd "$EXTRACT_DIR" && find . -maxdepth 2 -type f -printf '    %-24f %s bytes\n' | sort )

# --- Verify the removed binaries are gone -----------------------------------
for name in "${EXPECT_GONE[@]}"; do
  if find "$EXTRACT_DIR" \( -name "$name" -o -name "$name.exe" \) | grep -q .; then
    echo "ERROR: '$name' survived the strip — aborting." >&2
    exit 1
  fi
done

# --- Verify the kept binaries are present -----------------------------------
for name in "${EXPECT_KEEP[@]}"; do
  if ! find "$EXTRACT_DIR" \( -name "$name" -o -name "$name.exe" \) | grep -q .; then
    echo "ERROR: expected binary '$name' is missing from the archive — aborting." >&2
    exit 1
  fi
done

# --- Repackage --------------------------------------------------------------
# Preserve the archive's original top-level layout (official tarballs place the
# binaries at the archive root, i.e. "./sui"). Repack the same relative paths.
echo "==> Repackaging..."
mkdir -p "$(dirname "$OUTPUT")"
tar -c -z -f "$OUTPUT" -C "$EXTRACT_DIR" .

echo "==> Done."
echo "    $(du -h "$OUTPUT" | cut -f1)  $OUTPUT"
echo "==> Archive contents:"
tar -tzf "$OUTPUT" | sed 's/^/    /'
