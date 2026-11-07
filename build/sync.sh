#!/bin/bash
# Runs inside lineage-build:24 as user build, with the volume at /lin.
# Initialise (once) and sync LineageOS 24.0 plus the cancunf local manifest.
set -euo pipefail
mkdir -p /lin/src /lin/logs /lin/ccache
cd /lin/src
git config --global user.name  "lineage-build"
git config --global user.email "build@localhost"
git config --global color.ui false
if [ ! -d .repo ]; then
    repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs --depth=1
fi
mkdir -p .repo/local_manifests
cp /lin/manifests/cancunf.xml .repo/local_manifests/cancunf.xml
time repo sync -c -j"${SYNC_JOBS:-4}" --no-tags --no-clone-bundle --optimized-fetch --prune --force-sync
echo "SYNC-DONE $(date -u +%FT%TZ)"
du -sh /lin/src
