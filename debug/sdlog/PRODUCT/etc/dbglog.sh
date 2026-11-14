#!/system/bin/sh
# DEBUG-ONLY: stream boot logs to /metadata/dbglog/bootN (32 MB partition: keep it small).
B=/metadata/dbglog
mkdir -p $B || { mkdir -p /data/local/tmp/dbglog; B=/data/local/tmp/dbglog; }
echo "$(cut -d' ' -f1 /proc/uptime) dbglog start id=$(id) enforce=$(getenforce)" >> $B/status
# Keep only the newest previous boot.
n=0
while [ -e $B/boot$n ]; do n=$((n+1)); done
k=0
while [ $k -lt $((n-1)) ]; do rm -rf $B/boot$k; k=$((k+1)); done
D=$B/boot$n
mkdir -p $D
echo "started uptime=$(cat /proc/uptime) id=$(id)" > $D/started
getenforce >> $D/started 2>&1
sync
cat /proc/cmdline > $D/cmdline.txt 2>&1
cat /proc/bootconfig >> $D/cmdline.txt 2>&1
getprop > $D/getprop-early.txt 2>&1
logcat -b all -v threadtime -f $D/logcat.txt -r 2048 -n 4 > $D/logcat.err 2>&1 &
echo "logcat pid=$!" >> $D/started
t=0
while true; do
    sleep 5; t=$((t+5))
    if [ $((t % 15)) -eq 0 ]; then
        dmesg > $D/dmesg.txt 2>&1
        getprop > $D/getprop.txt 2>&1
        ps -A -o PID,PPID,S,TIME,NAME > $D/ps.txt 2>&1
        mkdir -p $D/tombstones $D/anr
        cp -f /data/tombstones/tombstone_0[0-9] $D/tombstones/ 2>/dev/null
        cp -f /data/anr/* $D/anr/ 2>/dev/null
        echo "alive t=$t uptime=$(cat /proc/uptime)" > $D/alive
    fi
    sync
done
