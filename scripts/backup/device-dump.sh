#!/system/bin/sh
# Runs ON THE PHONE as root (Magisk). Images every partition except userdata
# into $OUT and writes a sha256 manifest computed over the staged images.
#
#   adb push device-dump.sh /data/local/tmp/ && adb shell su -c 'sh /data/local/tmp/device-dump.sh'
#
# Partitions mounted read-write are frozen (FIFREEZE) for the duration of their
# copy so the image is a consistent filesystem state, then thawed. A trap thaws
# on any exit so a failure can't leave /metadata or nvdata frozen.

BB=/data/adb/magisk/busybox
OUT=/data/local/tmp/bk
BYNAME=/dev/block/by-name
BS=4194304

# Whole-LUN and alias entries: sda/sdb are the preloader LUNs (dumped whole as
# preloader_a/_b's real device), sdc is the main LUN (GPT captured separately),
# the rest are symlink aliases of devices already covered.
SKIP=" userdata sda sdb sdc bootloader1 bootloader2 preloader_emmc_a preloader_emmc_b preloader_ufs_a preloader_ufs_b preloader_raw_a preloader_raw_b "

FROZEN=""
thaw() {
    [ -n "$FROZEN" ] && $BB fsfreeze --unfreeze "$FROZEN" 2>/dev/null
    FROZEN=""
}
trap thaw EXIT INT TERM HUP

die() {
    echo "FATAL: $*"
    exit 1
}

[ "$(id -u)" = 0 ] || die "not root"

rm -rf "$OUT"
mkdir -p "$OUT" || die "mkdir $OUT"
: > "$OUT/SHA256SUMS"
: > "$OUT/dump.log"

# mountpoint for a block device if it is mounted rw, else empty
rw_mount() {
    dev=$1
    while read -r src mnt fs opts rest; do
        real=$(readlink -f "$src")
        [ "$real" = "$dev" ] || continue
        case ",$opts," in
            *,rw,*) echo "$mnt"; return ;;
        esac
    done < /proc/mounts
}

image() {
    name=$1
    dev=$2
    want=$($BB blockdev --getsize64 "$dev")
    mnt=$(rw_mount "$dev")

    if [ -n "$mnt" ]; then
        sync
        $BB fsfreeze --freeze "$mnt" || die "freeze $mnt"
        FROZEN=$mnt
    fi

    $BB dd if="$dev" of="$OUT/$name.img" bs=$BS 2>/dev/null
    rc=$?
    thaw
    [ $rc = 0 ] || die "dd $name rc=$rc"

    got=$($BB stat -c %s "$OUT/$name.img")
    [ "$got" = "$want" ] || die "$name size $got != $want"

    sum=$($BB sha256sum "$OUT/$name.img" | cut -d' ' -f1)
    echo "$sum  $name.img" >> "$OUT/SHA256SUMS"
    echo "$name $dev $want ${mnt:+frozen:$mnt}" >> "$OUT/dump.log"
    echo "ok $name $want ${mnt:+(frozen $mnt)}"
}

for link in "$BYNAME"/*; do
    name=${link##*/}
    case "$SKIP" in *" $name "*) continue ;; esac
    image "$name" "$(readlink -f "$link")"
done

# Main-LUN GPT: primary at the head, backup at the tail. 1 MiB each covers both
# with plenty of margin at the 4 KiB logical block size.
LUN=/dev/block/sdc
# The device shell's $(( )) is 32-bit: a 128 GB byte count overflows it. The
# 512-byte sector count (--getsz) fits, so derive 4 KiB blocks from that.
lun_blocks=$(( $($BB blockdev --getsz $LUN) / 8 ))
$BB dd if=$LUN of="$OUT/sdc_gpt_head.bin" bs=4096 count=256 2>/dev/null || die "gpt head"
$BB dd if=$LUN of="$OUT/sdc_gpt_tail.bin" bs=4096 skip=$((lun_blocks - 256)) count=256 2>/dev/null || die "gpt tail"
for f in sdc_gpt_head.bin sdc_gpt_tail.bin; do
    echo "$($BB sha256sum "$OUT/$f" | cut -d' ' -f1)  $f" >> "$OUT/SHA256SUMS"
done
echo "sdc_gpt tail_offset_blocks=$((lun_blocks - 256)) lun_blocks=$lun_blocks" >> "$OUT/dump.log"

# Filesystem sanity of the frozen ext4 images (read-only check on the copies).
for n in metadata nvcfg nvdata persist prodpersist protect1 protect2; do
    r=$(/system/bin/e2fsck -fn "$OUT/$n.img" 2>&1 | tail -1)
    echo "fsck $n: $r" | tee -a "$OUT/dump.log"
done

echo "DONE $(wc -l < "$OUT/SHA256SUMS") files, $($BB du -sh "$OUT" | cut -f1)"
