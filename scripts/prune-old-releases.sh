#!/usr/bin/env bash
#
# prune-old-releases.sh — retention policy for this repo's GitHub releases.
#
# Releases are grouped by "component": the tag name with its trailing
# "-v<version>" removed. For example:
#
#   site-builder-mainnet-v1.2.3  -> component "site-builder-mainnet"
#   site-builder-testnet-v1.2.3  -> component "site-builder-testnet"
#   seal-v0.5.9                  -> component "seal"
#   suibase-daemon-v0.0.17       -> component "suibase-daemon"
#   sui-testnet-v1.46.1          -> component "sui-testnet"
#
# Within each component group the newest KEEP releases (by semantic version)
# are retained; older releases are deleted, along with their git tag.
#
# The consuming install scripts always fetch the *latest* version of a
# component, so keeping a small buffer of previous versions only needs to
# cover edge cases / races where a client resolved an older "latest" moments
# before a newer release landed. KEEP=3 keeps the latest plus 2 previous.
#
# Usage:
#   ./scripts/prune-old-releases.sh                 # dry-run (default): list only
#   DRY_RUN=false ./scripts/prune-old-releases.sh   # actually delete
#   KEEP=3 DRY_RUN=false ./scripts/prune-old-releases.sh
#
# Requirements: gh (authenticated), jq, GNU sort.

set -euo pipefail

KEEP="${KEEP:-3}"             # releases to retain per component (latest + 2 previous)
DRY_RUN="${DRY_RUN:-true}"    # default to a safe dry-run; set "false" to delete
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || [ "$KEEP" -lt 1 ]; then
  echo "ERROR: KEEP must be a positive integer (got '$KEEP')" >&2
  exit 1
fi

echo "Repository : $REPO"
echo "Keep       : $KEEP most recent release(s) per component"
echo "Mode       : $([ "$DRY_RUN" = "false" ] && echo 'APPLY (deletions will happen)' || echo 'DRY-RUN (no deletions)')"
echo

# Emit "component<TAB>version<TAB>tag" for every published (non-draft) release
# whose tag carries a "-v<version>" suffix, sorted by component then by version
# descending (newest first), and mark everything past the KEEP-th for deletion.
classified="$(
  gh api --paginate "repos/$REPO/releases" \
    --jq '.[]
          | select(.draft == false)
          | select(.tag_name | test("-v[0-9]"))
          | [ (.tag_name | sub("-v[0-9].*$"; "")),
              (.tag_name | sub("^.*-v"; "")),
              .tag_name ]
          | @tsv' \
  | sort -t"$(printf '\t')" -k1,1 -k2,2Vr \
  | awk -F'\t' -v keep="$KEEP" '
      $1 != prev { prev = $1; n = 0 }
      { n++; printf "%s\t%s\t%s\t%s\n", (n > keep ? "DELETE" : "KEEP"), $1, $2, $3 }'
)"

if [ -z "$classified" ]; then
  echo "No releases found to evaluate."
  exit 0
fi

# Per-component summary (kept / to-delete).
echo "Per-component summary:"
awk -F'\t' '
  { total[$2]++; if ($1 == "DELETE") del[$2]++ }
  END {
    for (c in total)
      printf "  %-26s %d release(s), %d to delete\n", c, total[c], (del[c] ? del[c] : 0)
  }' <<<"$classified" | sort
echo

# Collect the tags marked for deletion.
mapfile -t to_delete < <(awk -F'\t' '$1 == "DELETE" { print $4 }' <<<"$classified")

if [ "${#to_delete[@]}" -eq 0 ]; then
  echo "Nothing to prune — every component is within the retention limit."
  exit 0
fi

echo "${#to_delete[@]} release(s) to delete:"
printf '  %s\n' "${to_delete[@]}"
echo

if [ "$DRY_RUN" != "false" ]; then
  echo "DRY-RUN: no releases deleted. Re-run with DRY_RUN=false to apply."
  exit 0
fi

for tag in "${to_delete[@]}"; do
  echo "Deleting release and tag: $tag"
  gh release delete "$tag" --repo "$REPO" --cleanup-tag --yes
done

echo
echo "Done. Deleted ${#to_delete[@]} release(s)."
