#!/bin/bash
# Make a signed incremental OTA from one signed build to another.
#
#   build/incremental.sh <source id>               # to the newest build
#   build/incremental.sh <source id> <target id>
#
# Both builds must have their signed target files in /lin/release/<id>/
# (build/sign.sh keeps them). The output goes next to the target's full OTA:
#   /lin/release/<target>/lineage-...-cancunf-incr-<source>-signed.zip
# An existing output is checked and kept, so publish.sh can call this freely.
#
# update_engine checks the source partitions' hashes before writing, so an
# incremental applied to the wrong build fails without touching the phone.
set -euo pipefail

VOL=${VOL:-lineage-build}
IMAGE=${IMAGE:-lineage-build:24}

src=${1:-}
tgt=${2:-}
[[ $src =~ ^[0-9]+$ ]] || { echo "usage: $0 <source id> [target id]" >&2; exit 1; }
[ -z "$tgt" ] || [[ $tgt =~ ^[0-9]+$ ]] || { echo "bad target id: $tgt" >&2; exit 1; }

"$(dirname "$0")/ensure-volume.sh" >/dev/null

docker run --rm --name "lineage-incr-$src" --memory=8g --cpus=4 \
    -v "$VOL":/lin -e SRC="$src" -e TGT="$tgt" "$IMAGE" bash -c '
    set -euo pipefail
    K=/lin/keys
    R=/lin/release
    cd /lin/src
    [ -n "$TGT" ] || TGT=$(ls -1 "$R" | grep -E "^[0-9]+$" | sort -n | tail -1)
    [ "$SRC" -lt "$TGT" ] || { echo "source $SRC is not older than target $TGT" >&2; exit 1; }

    src_tf=$R/$SRC/lineage_cancunf-$SRC-signed-target_files.zip
    tgt_tf=$R/$TGT/lineage_cancunf-$TGT-signed-target_files.zip
    for f in "$src_tf" "$tgt_tf"; do
        [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }
    done
    full=$(ls "$R/$TGT"/lineage-*-signed.zip | grep -v -- "-incr-" | head -1)
    [ -n "$full" ] || { echo "no full OTA in $R/$TGT; run build/sign.sh" >&2; exit 1; }
    out=${full%-signed.zip}-incr-$SRC-signed.zip

    # The package must say it goes from SRC to TGT, as an A/B payload.
    check() {
        local m
        m=$(unzip -p "$1" META-INF/com/android/metadata)
        p() { echo "$m" | sed -n "s/^$1=//p" | head -1; }
        [ "$(p ota-type)" = AB ] &&
        [ "$(p pre-build-incremental)" = "$SRC" ] &&
        [ "$(p post-build-incremental)" = "$TGT" ]
    }

    if [ -s "$out" ]; then
        check "$out" || { echo "$out exists but its metadata is not $SRC -> $TGT" >&2; exit 1; }
        echo "kept $out"
        exit 0
    fi

    [ -s "$K/releasekey.pk8" ] || { echo "no release keys in $K" >&2; exit 1; }
    export PATH=$PWD/out/host/linux-x86/bin:$PWD/prebuilts/jdk/jdk21/linux-x86/bin:$PATH
    echo "incremental $SRC -> $TGT"
    ota_from_target_files --path out/host/linux-x86 -k "$K/releasekey" \
        -i "$src_tf" "$tgt_tf" "$out.tmp"
    check "$out.tmp" || { echo "generated package metadata is not $SRC -> $TGT" >&2; exit 1; }
    mv "$out.tmp" "$out"

    ( cd "$R/$TGT" && sha256sum *.zip > SHA256SUMS )
    ls -la "$out"
'
