#!/bin/bash
# Point Docker volume "$VOL" at the ext4 disk labelled "$LABEL".
#
# Docker Desktop's daemon has its own mount namespace: a bind mount of
# /mnt/wsl/<name> reaches a stray directory, not the attached VHDX. The disk
# is visible to it as a raw block device though (one shared VM kernel), so the
# volume mounts the device directly. The device letter can change when WSL
# re-attaches disks, so it is looked up by label each time.
set -euo pipefail

LABEL=${LABEL:-lineage}
VOL=${VOL:-lineage-build}

dev=$(docker run --rm --privileged alpine blkid 2>/dev/null \
      | awk -F: -v l="LABEL=\"$LABEL\"" 'index($0, l) && /TYPE="ext4"/ {print $1; exit}' || true)
if [ -z "$dev" ]; then
    echo "no ext4 disk labelled '$LABEL' is attached; run scripts/windows/attach-build-disk.ps1 (elevated)" >&2
    exit 1
fi

cur=$(docker volume inspect -f '{{index .Options "device"}}' "$VOL" 2>/dev/null || true)
if [ "$cur" = "$dev" ]; then
    echo "volume $VOL -> $dev (ok)"
    exit 0
fi

if [ -n "$cur" ]; then
    if docker ps -q --filter volume="$VOL" | grep -q .; then
        echo "volume $VOL points at $cur but the disk is $dev and a container uses it; stop it first" >&2
        exit 1
    fi
    docker volume rm "$VOL" >/dev/null
fi
docker volume create --driver local --opt type=ext4 --opt device="$dev" --opt o=noatime "$VOL" >/dev/null
echo "volume $VOL -> $dev (recreated, was: ${cur:-none})"
