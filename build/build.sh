#!/bin/bash
# Launch a LineageOS build for cancunf in a memory-capped container.
#
# The cap is the point: an out-of-memory condition must kill only this
# container, never the shared WSL/Docker VM. Soong sizes its highmem job pool
# from /proc/meminfo, which shows the whole VM rather than the cgroup cap, so
# the pool is pinned explicitly.
#
#   build/build.sh                 # m bacon, userdebug
#   TARGET=installclean build/build.sh
set -euo pipefail

VOL=${VOL:-lineage-build}
IMAGE=${IMAGE:-lineage-build:24}
MEM=${MEM:-12g}
MEMSWAP=${MEMSWAP:-24g}       # RAM + swap the container may use; keep below the VM's swap
CPUS=${CPUS:-10}
JOBS=${JOBS:-10}
TARGET=${TARGET:-bacon}
VARIANT=${VARIANT:-userdebug}

"$(dirname "$0")/ensure-volume.sh"

docker run --rm --name lineage-build \
    --memory="$MEM" --memory-swap="$MEMSWAP" --cpus="$CPUS" --cpu-shares=256 \
    -e NINJA_HIGHMEM_NUM_JOBS=1 -e JOBS="$JOBS" -e TARGET="$TARGET" -e VARIANT="$VARIANT" \
    -v "$VOL":/lin "$IMAGE" bash -c '
        set -eo pipefail
        log=/lin/logs/build-$(date -u +%Y%m%dT%H%M%SZ).log
        exec > >(tee "$log") 2>&1
        ccache -M 50G >/dev/null
        cd /lin/src
        export WITH_DEXPREOPT=false
        source build/envsetup.sh
        breakfast cancunf "$VARIANT"
        start=$(date +%s)
        rc=0
        nice -n 10 m -j"$JOBS" "$TARGET" || rc=$?
        echo "BUILD rc=$rc elapsed=$(( $(date +%s) - start ))s"
        echo "cgroup memory.peak=$(cat /sys/fs/cgroup/memory.peak 2>/dev/null) swap.peak=$(cat /sys/fs/cgroup/memory.swap.peak 2>/dev/null)"
        echo "oom events: $(grep -E "^(oom|oom_kill) " /sys/fs/cgroup/memory.events 2>/dev/null | tr "\n" " ")"
        exit $rc
    '
