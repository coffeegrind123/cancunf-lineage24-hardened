#!/system/bin/sh
# DEBUG-ONLY: runs in recovery. Finds the SD card via sysfs, then every 20 s for
# 5 minutes copies /metadata/dbglog and recovery's own state to <sd>/dbglog-recN/.
ST=/tmp/dbgcopy.status
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >> $ST; }
log "start id=$(id) enforce=$(getenforce)"

find_sd() {
    for p in /sys/devices/platform/soc/11240000.mmc/mmc_host/*/*/block/*/*p1 \
             /sys/block/mmcblk*/mmcblk*p1; do
        [ -e "$p/dev" ] || continue
        echo "$p"; return 0
    done
    return 1
}

M=/dev/dbgmeta; S=/dev/dbgsd; mkdir -p $M $S
i=0; sp=""
while [ $i -lt 90 ]; do sp=$(find_sd) && break; sleep 1; i=$((i+1)); done
log "sysfs=$sp"
[ -n "$sp" ] || { ls -laR /sys/devices/platform/soc/11240000.mmc >> $ST 2>&1; exit 1; }
name=$(basename $sp); mm=$(cat $sp/dev)
dev=/dev/block/$name
if [ ! -b $dev ]; then
    dev=/dev/dbgsdblk
    mknod $dev b ${mm%%:*} ${mm##*:}
fi
log "dev=$dev ($mm)"

n=-1
k=0
while [ $k -lt 15 ]; do
    sleep 20; k=$((k+1))
    ok=0
    for o in "-t vfat -o rw,sync" "-t vfat" "-t auto"; do
        if mount $o $dev $S 2>>$ST; then ok=1; log "mounted with: $o"; break; fi
        log "mount failed: $o"
    done
    [ $ok -eq 1 ] || continue
    if [ $n -lt 0 ]; then
        n=0; while [ -e $S/dbglog-rec$n ]; do n=$((n+1)); done
    fi
    D=$S/dbglog-rec$n; R=$D/recovery-$k
    mkdir -p $R
    if mount -t ext4 -o ro /dev/block/by-name/metadata $M 2>>$ST || mountpoint -q $M; then
        rm -rf $D/dbglog; cp -r $M/dbglog $D/ 2>>$ST
        ls -laR $M > $D/metadata-ls.txt 2>&1
        umount $M
    else
        log "metadata mount failed"
    fi
    dmesg > $R/dmesg.txt 2>&1
    getprop > $R/getprop.txt 2>&1
    cp /tmp/recovery.log $R/ 2>/dev/null
    { ls -la /sys/class/udc/
      for f in /sys/class/udc/*/state /sys/class/udc/*/current_speed; do echo "$f: $(cat $f 2>&1)"; done
      ls -laR /config/usb_gadget 2>&1 | head -200
      for f in /sys/class/typec/port0/*; do [ -f $f ] && echo "$f: $(cat $f 2>&1)"; done
      lsmod; ps -A; } > $R/usb.txt 2>&1
    cp $ST $D/dbgcopy.status
    sync
    umount $S
done
log "done"
