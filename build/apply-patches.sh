#!/bin/bash
# Re-apply this repo's patches on top of the synced tree. Runs inside the
# build container with the repo's patches/ mounted at /lin/manifests/patches.
#
# patches/<project_with_underscores>/NNNN-*.patch maps to the project path
# from the local manifest, e.g. device_motorola_cancunf -> device/motorola/cancunf.
# Each project gets a local "lineage" branch on top of the synced revision, so
# `repo sync` can move the base and this script reapplies cleanly.
set -euo pipefail

SRC=${SRC:-/lin/src}
PATCHES=${PATCHES:-/lin/manifests/patches}

declare -A PATHS=(
    [device_motorola_cancunf]=device/motorola/cancunf
)

for proj in "${!PATHS[@]}"; do
    dir="$SRC/${PATHS[$proj]}"
    [ -d "$PATCHES/$proj" ] || continue
    cd "$dir"
    git config user.name lineage-build
    git config user.email build@localhost

    # Base = whatever repo checked out (the manifest revision).
    base=$(git rev-parse "m/lineage-24.0" 2>/dev/null || git rev-parse "HEAD@{upstream}" 2>/dev/null || git rev-parse HEAD)
    git checkout -q -B lineage "$base"
    git am -q --3way "$PATCHES/$proj"/*.patch
    echo "$proj: $(git log --oneline "$base"..HEAD | wc -l) patch(es) on $(git rev-parse --short "$base")"
done
