#!/bin/bash
# Compressed RAM swap (zram) for the Docker Desktop / WSL2 VM, so Soong
# analysis, which needs far more memory than the VM has, can run without disk
# swap. Disk swap is what froze the VM on 2026-11-10: every GC cycle walks the
# whole heap, and paging that through a VHDX stalls everything. zram pages
# cost CPU instead of I/O.
#
#   build/zram.sh on       # load zram, make it the only swap
#   build/zram.sh off      # back to the VM's disk swap
#   build/zram.sh status
#
# Runtime only: a VM restart restores the defaults. The settings are VM-wide,
# so every container shares them while zram is on.
#
#   ZRAM_DISKSIZE  uncompressed capacity          (default 40G)
#   ZRAM_MEMLIMIT  cap on the compressed pool     (default 10G); when it is
#                  full, swap-out fails and the build stalls until
#                  build.sh's pressure watchdog kills it. Analysis peaked
#                  at 8.75 GiB of pool on 2026-11-14 with other workloads
#                  holding ~3 GiB of it; an 8G cap killed two runs.
#                  mem_limit is write-only and can be raised live:
#                  echo 10G > /sys/block/zram0/mem_limit (read mm_stat).
set -euo pipefail

ZRAM_DISKSIZE=${ZRAM_DISKSIZE:-40G}
ZRAM_MEMLIMIT=${ZRAM_MEMLIMIT:-10G}

# The VM's kernel is shared by all containers; a privileged one can load the
# module and manage swap for the whole VM.
vm() {
    docker run --rm --privileged -v /lib/modules:/lib/modules:ro -v /dev:/dev \
        -e ZRAM_DISKSIZE="$ZRAM_DISKSIZE" -e ZRAM_MEMLIMIT="$ZRAM_MEMLIMIT" \
        alpine sh -euc "$1"
}

case "${1:-status}" in
on)
    vm '
        if ! grep -q "zram0 " /proc/swaps; then
            [ -e /sys/block/zram0 ] || modprobe zram
            echo 1 > /sys/block/zram0/reset 2>/dev/null || true
            echo "$ZRAM_DISKSIZE" > /sys/block/zram0/disksize
            echo "$ZRAM_MEMLIMIT" > /sys/block/zram0/mem_limit
            mkswap /dev/zram0 >/dev/null
            swapon -p 100 /dev/zram0
        fi
        # zram has no seek cost: swap eagerly, one page at a time.
        echo 180 > /proc/sys/vm/swappiness
        echo 0 > /proc/sys/vm/page-cluster
        # Move what sits on disk swap into RAM/zram, then leave zram alone.
        for dev in $(awk "NR > 1 && \$1 !~ /zram0\$/ {print \$1}" /proc/swaps); do
            echo "swapoff $dev (can take a minute)"
            swapoff "$dev"
            echo "$dev" >> /dev/shm/zram-disabled-swaps
        done
        cat /proc/swaps
    '
    ;;
off)
    vm '
        for dev in $(sort -u /dev/shm/zram-disabled-swaps 2>/dev/null); do
            grep -q "^$dev " /proc/swaps || swapon "$dev"
        done
        rm -f /dev/shm/zram-disabled-swaps
        if grep -q "zram0 " /proc/swaps; then
            swapoff /dev/zram0
            echo 1 > /sys/block/zram0/reset
        fi
        echo 60 > /proc/sys/vm/swappiness
        echo 2 > /proc/sys/vm/page-cluster
        cat /proc/swaps
    '
    ;;
status)
    vm '
        cat /proc/swaps
        echo "swappiness=$(cat /proc/sys/vm/swappiness) page-cluster=$(cat /proc/sys/vm/page-cluster)"
        if [ -e /sys/block/zram0/mm_stat ]; then
            # mm_stat: orig_data compr_data mem_used mem_limit ...
            awk "{printf \"zram: %.1f GiB stored in %.1f GiB (limit %.1f GiB), ratio %.1f\n\", \$1/2^30, \$3/2^30, \$4/2^30, (\$3 ? \$1/\$3 : 0)}" /sys/block/zram0/mm_stat
        fi
        grep -E "^(MemTotal|MemAvailable|SwapTotal|SwapFree):" /proc/meminfo
    '
    ;;
*)
    echo "usage: $0 on|off|status" >&2
    exit 2
    ;;
esac
