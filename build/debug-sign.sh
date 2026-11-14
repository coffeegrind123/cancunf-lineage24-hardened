#!/bin/bash
# Make a signed DEBUG OTA: the current build plus an overlay of extra files.
#
#   build/debug-sign.sh debug/sdlog          # -> /lin/release/debug-sdlog-<build id>/
#
# The overlay directory mirrors target-files paths (PRODUCT/etc/...,
# VENDOR_BOOT/RAMDISK_FRAGMENTS/recovery/RAMDISK/...). Its files are added to
# the unsigned target-files package, then the package is signed exactly as
# build/sign.sh does, so the debug OTA installs over a release build and the
# AVB/verity metadata covers the added files. Nothing is recompiled.
#
# Debug OTAs are for diagnosis only. Never publish one.
set -euo pipefail

overlay=${1:?usage: $0 <overlay dir> [name]}
name=${2:-$(basename "$overlay")}
[ -d "$overlay" ] || { echo "no overlay directory: $overlay" >&2; exit 1; }

VOL=${VOL:-lineage-build}
IMAGE=${IMAGE:-lineage-build:24}

# Partitions the overlay may touch, with their filesystem config in META/.
# VENDOR_BOOT ramdisk fragments are packed without a filesystem config.
for top in $(cd "$overlay" && find . -mindepth 1 -maxdepth 1 -type d | sed 's|^\./||'); do
    case $top in
        PRODUCT|SYSTEM_EXT|VENDOR|VENDOR_BOOT) ;;
        *) echo "overlay may only contain PRODUCT, SYSTEM_EXT, VENDOR, VENDOR_BOOT (found $top)" >&2; exit 1 ;;
    esac
done

"$(dirname "$0")/ensure-volume.sh"

# The overlay goes in over stdin: the repo may sit where Docker cannot bind-mount it.
tar -C "$overlay" -cf - . | docker run --rm -i --name lineage-debug-sign --memory=8g --cpus=4 \
    -v "$VOL":/lin -e NAME="$name" "$IMAGE" bash -c '
    set -euo pipefail
    K=/lin/keys
    cd /lin/src
    [ -s "$K/releasekey.pk8" ] || { echo "no release keys in $K; run build/keys.sh" >&2; exit 1; }

    TF=$(ls -t out/target/product/cancunf/obj/PACKAGING/target_files_intermediates/*-target_files*.zip | head -1)
    id=$(unzip -p "$TF" SYSTEM/build.prop | sed -n "s/^ro.build.version.incremental=//p")
    out=/lin/release/debug-$NAME-$id
    W=$out/work
    rm -rf "$W"; mkdir -p "$W/overlay"
    tar -C "$W/overlay" -xf -
    echo "target files: $TF (build $id); overlay $NAME"

    cp "$TF" "$W/tf.zip"
    cp -r "$W/overlay/." "$W/"
    files=$(cd "$W/overlay" && find . -type f | sed "s|^\./||" | sort)
    [ -n "$files" ] || { echo "overlay is empty" >&2; exit 1; }
    (cd "$W" && chmod 644 $files)

    # Every added file and directory needs an entry in its partition config,
    # or the image build gives it default ownership and mode.
    mkdir -p "$W/META"
    configs=""
    for f in $files; do
        top=${f%%/*}
        [ "$top" = VENDOR_BOOT ] && continue
        part=$(echo "$top" | tr A-Z a-z)
        cfg=META/${part}_filesystem_config.txt
        [ -f "$W/$cfg" ] || unzip -p "$TF" "$cfg" > "$W/$cfg"
        rel=$part/${f#*/}
        d=$(dirname "$rel")
        while [ "$d" != "$part" ] && [ "$d" != . ]; do
            grep -q "^$d " "$W/$cfg" || echo "$d 0 0 755 capabilities=0x0" >> "$W/$cfg"
            d=$(dirname "$d")
        done
        grep -q "^$rel " "$W/$cfg" || echo "$rel 0 0 644 capabilities=0x0" >> "$W/$cfg"
        case " $configs " in *" $cfg "*) ;; *) configs="$configs $cfg" ;; esac
    done
    for cfg in $configs; do sort -o "$W/$cfg" "$W/$cfg"; done
    (cd "$W" && zip -q tf.zip $files $configs)
    echo "== added:"; echo "$files"

    # Images in the unsigned package are stale now; sign_target_files_apks
    # regenerates every image (and vbmeta) from the patched tree.
    zip -q -d "$W/tf.zip" "IMAGES/*" || true

    export PATH=$PWD/out/host/linux-x86/bin:$PWD/prebuilts/jdk/jdk21/linux-x86/bin:$PATH
    tools="--path out/host/linux-x86"
    apex_args=()
    for apex in $(unzip -p "$TF" META/apexkeys.txt | grep -oE "^name=\"[^\"]+\.apex\"" | sed -E "s/^name=\"(.*)\"$/\1/"); do
        k=${apex%.apex}
        [ -s "$K/$k.pem" ] || { echo "no key for $apex; run build/keys.sh" >&2; exit 1; }
        apex_args+=(--extra_apks "$apex=$K/$k" --extra_apex_payload_key "$apex=$K/$k.pem")
    done

    stf=$out/debug-signed-target_files.zip
    sign_target_files_apks $tools -o -d "$K" "${apex_args[@]}" \
        --avb_vbmeta_key "$K/avb.pem" --avb_vbmeta_algorithm SHA256_RSA4096 \
        --avb_vbmeta_system_key "$K/avb.pem" --avb_vbmeta_system_algorithm SHA256_RSA4096 \
        "$W/tf.zip" "$stf"

    ota=$out/lineage-DEBUG-$NAME-signed.zip
    ota_from_target_files $tools -k "$K/releasekey" "$stf" "$ota"
    rm -rf "$W"
    ( cd "$out" && sha256sum *.zip > SHA256SUMS )
    ls -la "$out"
'
