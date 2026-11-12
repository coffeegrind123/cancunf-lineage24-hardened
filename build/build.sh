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

# Android 17 Soong analysis holds over 30 GB (measured 2026-11-11: ~8 GB RAM
# plus ~26 GB in zram), far more than the VM's 22 GB. It completes only with
# compressed RAM swap (build/zram.sh on); disk swap froze the whole VM on
# 2026-11-10, because every Go GC cycle walks the entire heap.
if docker run --rm alpine grep -q 'zram0 ' /proc/swaps 2>/dev/null; then
    # zram is the only swap: give the build most of it, keep RAM for the VM.
    MEM=${MEM:-8g}
    MEMSWAP=${MEMSWAP:-48g}
    GOGC=${GOGC:-30}      # trade GC CPU for a smaller heap; every page of it is swapped
    # siso holds ~5 GB of the 8 GiB, and every javac gets a 4 GB heap. At -j10
    # the Java-heavy part of the build thrashed (57% full stall for an hour,
    # 2026-11-12); 5 jobs keeps the working set mostly in RAM.
    JOBS=${JOBS:-5}
    # Healthy zram runs sit at 8-20% full stall, the thrash at 55-60%.
    PSI_KILL=${PSI_KILL:-45}
else
    # No zram: the build cannot finish analysis, but must not take the VM with it.
    MEM=${MEM:-12g}
    MEMSWAP=${MEMSWAP:-$MEM}
fi
JOBS=${JOBS:-10}
CPUS=${CPUS:-10}
TARGET=${TARGET:-bacon}
VARIANT=${VARIANT:-userdebug}

"$(dirname "$0")/ensure-volume.sh"

# Memory controls for Soong analysis, passed through only when set:
#   GOMEMLIMIT=9GiB                    soft heap limit for soong_build (Go GC works harder)
#   SOONG_INCREMENTAL_ANALYSIS=false   overrides the release flag that turns it on
passthru=()
for v in GOMEMLIMIT GOGC GODEBUG SOONG_INCREMENTAL_ANALYSIS SOONG_PERIODIC_MEMPROFILE PSI_KILL VM_MIN_MB DISABLE_HOST_CROSS_WINDOWS; do
    if [ -n "${!v:-}" ]; then
        passthru+=(-e "$v=${!v}")
    fi
done

docker run --rm --name lineage-build \
    --memory="$MEM" --memory-swap="$MEMSWAP" --cpus="$CPUS" --cpu-shares=256 \
    -e NINJA_HIGHMEM_NUM_JOBS=1 -e JOBS="$JOBS" -e TARGET="$TARGET" -e VARIANT="$VARIANT" \
    "${passthru[@]}" \
    -v "$VOL":/lin "$IMAGE" bash -c '
        set -eo pipefail
        log=/lin/logs/build-$(date -u +%Y%m%dT%H%M%SZ).log
        exec > >(tee "$log") 2>&1
        ccache -M 50G >/dev/null
        cd /lin/src
        export WITH_DEXPREOPT=false
        export DISABLE_HOST_CROSS_WINDOWS=${DISABLE_HOST_CROSS_WINDOWS:-true}  # build/make patch 0001
        source build/envsetup.sh
        breakfast cancunf "$VARIANT"
        start=$(date +%s)

        # Memory trace: cgroup usage plus the three largest processes, every 10 s,
        # so an overrun shows which phase (soong_build, kati, siso) caused it.
        memlog=${log%.log}.mem.log
        ( set +eo pipefail
          while sleep 10; do
              printf "%s cur=%s " "$(( $(date +%s) - start ))s" "$(cat /sys/fs/cgroup/memory.current)"
              ps -eo rss=,comm= --sort=-rss | head -3 | awk "{printf \"%s:%dM \", \$2, \$1/1024}"
              echo
          done > "$memlog" ) &
        sampler=$!

        # Pressure watchdog. At the cgroup limit the kernel evicts file cache
        # (the binaries own pages included) rather than OOM-killing, so the
        # build stalls for minutes while the VM runs out of free memory; on
        # 2026-11-10 that took the Docker Desktop VM down. Kill the build once
        # the cgroup "full" stall share stays at or above PSI_KILL% for 6
        # samples (60 s). A GC-bound heap at the limit sat near 40% for minutes,
        # so the default is 25.
        #
        # VM guard: /proc/meminfo here is the whole VM, not the cgroup. With
        # zram the cgroup is allowed far past the VM RAM, so the thing to
        # protect is the VM itself: kill the build when VM MemAvailable stays
        # under VM_MIN_MB for 30 s.
        ( set +eo pipefail
          hits=0
          low=0
          while sleep 10; do
              full=$(awk "/^full/ {split(\$2, a, \"=\"); print int(a[2])}" /sys/fs/cgroup/memory.pressure)
              if [ "${full:-0}" -ge "${PSI_KILL:-25}" ]; then hits=$((hits + 1)); else hits=0; fi
              if [ "$hits" -ge 6 ]; then
                  echo "PRESSURE KILL: memory full stall avg10=${full}% for 60s; $(tail -n 1 "$memlog")"
                  kill -KILL -1
              fi
              avail=$(awk "/^MemAvailable/ {print int(\$2 / 1024)}" /proc/meminfo)
              if [ "${avail:-0}" -lt "${VM_MIN_MB:-700}" ]; then low=$((low + 1)); else low=0; fi
              if [ "$low" -ge 3 ]; then
                  echo "VM GUARD KILL: VM MemAvailable ${avail} MB for 30s; $(tail -n 1 "$memlog")"
                  kill -KILL -1
              fi
          done ) &

        rc=0
        nice -n 10 m -j"$JOBS" "$TARGET" || rc=$?
        kill "$sampler" 2>/dev/null || true
        echo "BUILD rc=$rc elapsed=$(( $(date +%s) - start ))s"
        echo "memory trace: $memlog (last: $(tail -n 1 "$memlog"))"
        echo "cgroup memory.peak=$(cat /sys/fs/cgroup/memory.peak 2>/dev/null) swap.peak=$(cat /sys/fs/cgroup/memory.swap.peak 2>/dev/null)"
        echo "oom events: $(grep -E "^(oom|oom_kill) " /sys/fs/cgroup/memory.events 2>/dev/null | tr "\n" " ")"
        exit $rc
    '
