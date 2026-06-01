#!/bin/bash

set -euo pipefail

# Get Latest Sui Version Script
#
# Resolves the latest official MystenLabs/sui release version for a given
# network (mainnet, testnet or devnet). Official releases are tagged
# "<network>-v<X.Y.Z>" (e.g. "testnet-v1.73.0").
#
# Used by the sui-min release workflow (and locally) to decide which upstream
# release to mirror, and to avoid re-mirroring an existing version.
#
# Usage:
#   get-latest-sui-version.sh <network> [version]
#   SUI_VERSION=1.73.0 get-latest-sui-version.sh <network>
#
# Output: bare semver on stdout, e.g. "1.73.0"
#
# Notes:
#   - devnet releases are published as GitHub "prereleases"; mainnet/testnet
#     are stable. We therefore do NOT filter on the prerelease flag and instead
#     match strictly on the "<network>-vX.Y.Z" tag shape (no -rc/-alpha suffix).
#   - Releases are returned newest-first by the API; we take the first match,
#     i.e. the most recently published release for that network.

RED='\033[0;31m'
NC='\033[0m'
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

NETWORK="${1:?usage: get-latest-sui-version.sh <network> [version]}"
VERSION="${2:-${SUI_VERSION:-latest}}"

case "$NETWORK" in
  mainnet|testnet|devnet) ;;
  *) log_error "Unknown network '$NETWORK' (expected mainnet|testnet|devnet)"; exit 1 ;;
esac

if [[ "$VERSION" == "latest" ]]; then
  # Authenticated calls (GH_TOKEN) get a higher rate limit in CI; fall back to
  # anonymous when no token is present.
  auth_header=()
  if [[ -n "${GH_TOKEN:-}" ]]; then
    auth_header=(--header "Authorization: Bearer ${GH_TOKEN}")
  fi

  latest_tag=$(curl -s "${auth_header[@]}" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/MystenLabs/sui/releases?per_page=100" | \
    jq -r '.[].tag_name' | \
    grep -E "^${NETWORK}-v[0-9]+\.[0-9]+\.[0-9]+$" | \
    head -n 1)

  if [[ -z "$latest_tag" ]]; then
    log_error "Failed to find a '${NETWORK}-vX.Y.Z' release from the GitHub API"
    exit 1
  fi
  VERSION="$latest_tag"
fi

# Normalize: strip optional "<network>-v" / "v" prefix down to bare semver.
VERSION="${VERSION#${NETWORK}-}"
VERSION="${VERSION#v}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  log_error "Invalid version format: '$VERSION' (expected X.Y.Z)"
  exit 1
fi

echo "$VERSION"
