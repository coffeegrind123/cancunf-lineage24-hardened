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
BRANCH=${BRANCH:-lineage}   # another name lets a scratch worktree verify without moving the live branch

declare -A PATHS=(
    [device_motorola_cancunf]=device/motorola/cancunf
    [vendor_motorola_cancunf]=vendor/motorola/cancunf
    [build_blueprint]=build/blueprint
    [build_make]=build/make
    [build_soong]=build/soong
    [packages_apps_DisplayFeatures]=packages/apps/DisplayFeatures
)

# Binary edits to vendor blobs. They can't ship as patches because this repo
# carries no proprietary files, so they run here, after that project's text
# patches, and are committed on the same "lineage" branch. Each must produce
# what the device tree's extract-files.py fixups would produce on re-extraction.
PATCHELF="$SRC/prebuilts/extract-tools/linux-x86/bin/patchelf-0_18"

blobfix_vendor_motorola_cancunf() {
    local p=proprietary/vendor

    # libmnl -> libmnl_mtk (FIX_SONAME), mnld re-linked: device patch 0003.
    git mv "$p/lib64/mt6855/libmnl.so" "$p/lib64/mt6855/libmnl_mtk.so"
    "$PATCHELF" --set-soname libmnl_mtk.so "$p/lib64/mt6855/libmnl_mtk.so"
    "$PATCHELF" --replace-needed libmnl.so libmnl_mtk.so "$p/bin/mnld"

    # libformatter -> libformatter_mtk, codec2 libs re-linked; libladder and
    # wlan_assistant come from hardware/mediatek instead: device patch 0006.
    git mv "$p/lib64/libformatter.so" "$p/lib64/libformatter_mtk.so"
    "$PATCHELF" --set-soname libformatter_mtk.so "$p/lib64/libformatter_mtk.so"
    local lib
    for lib in libcodec2_mtk_vdec libcodec2_mtk_venc; do
        "$PATCHELF" --replace-needed libformatter.so libformatter_mtk.so "$p/lib64/$lib.so"
    done
    git rm -q "$p/lib/libladder.so" "$p/lib64/libladder.so" \
        "$p/bin/wlan_assistant" "$p/etc/init/wlan_assistant.rc"

    git add -A "$p"
    git commit -q -m "cancunf: Apply blob fixups from apply-patches.sh"
}

for proj in "${!PATHS[@]}"; do
    dir="$SRC/${PATHS[$proj]}"
    [ -d "$PATCHES/$proj" ] || continue
    cd "$dir"
    git config user.name lineage-build
    git config user.email build@localhost

    # Base = whatever repo checked out (the manifest revision).
    base=$(git rev-parse "m/lineage-24.0" 2>/dev/null || git rev-parse "HEAD@{upstream}" 2>/dev/null || git rev-parse HEAD)
    git checkout -q -B "$BRANCH" "$base"
    git am -q --3way "$PATCHES/$proj"/*.patch
    if declare -F "blobfix_$proj" >/dev/null; then
        "blobfix_$proj"
    fi
    echo "$proj: $(git log --oneline "$base"..HEAD | wc -l) patch(es) on $(git rev-parse --short "$base")"
done
