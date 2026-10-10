#!/usr/bin/env bash
# Apply OneClick's Wine patch series (Scripts/patches/wine/*.patch, lexical order) to a pristine CrossOver
# Wine source tree. Used by both Scripts/build-wine.sh and .github/workflows/build-wine.yml so the local and
# CI builds can't drift. Fails on the first patch that doesn't apply cleanly — never builds a half-patched tree.
#
# usage: Scripts/apply-wine-patches.sh <wine-source-dir>
set -euo pipefail
SRC="${1:?usage: apply-wine-patches.sh <wine-source-dir>}"
DIR="$(cd "$(dirname "$0")" && pwd)/patches/wine"
shopt -s nullglob
patches=("$DIR"/*.patch)
if [ "${#patches[@]}" -eq 0 ]; then echo "==> No Wine patches to apply"; exit 0; fi
for p in "${patches[@]}"; do
  echo "==> Applying $(basename "$p")"
  patch -d "$SRC" -p1 --forward --no-backup-if-mismatch --batch < "$p" \
    || { echo "ERROR: $(basename "$p") does not apply to $SRC" >&2; exit 1; }
done
echo "==> Applied ${#patches[@]} Wine patch(es)"
