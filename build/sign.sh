#!/bin/bash
# Sign a finished build with the release keys and make the release packages.
#
#   build/keys.sh                         # once
#   TARGET=target-files-package build/build.sh
#   build/sign.sh
#
# Output goes to /lin/release/<build id>/:
#   *-signed-target_files.zip   keep every published one: incrementals need it
#   lineage-*-signed.zip         the full OTA, signed with releasekey
#   *-signed-img.zip             fastboot images (boot, vendor_boot, ...) for the
#                                first install
# Nothing is recompiled: APKs, APEXes, AVB and the OTA certificate are re-signed
# in the target-files package.
set -euo pipefail

VOL=${VOL:-lineage-build}
IMAGE=${IMAGE:-lineage-build:24}

"$(dirname "$0")/ensure-volume.sh"

docker run --rm --name lineage-sign --memory=8g --cpus=4 -v "$VOL":/lin "$IMAGE" bash -c '
    set -euo pipefail
    K=/lin/keys
    cd /lin/src
    [ -s "$K/releasekey.pk8" ] || { echo "no release keys in $K; run build/keys.sh" >&2; exit 1; }

    TF=$(ls -t out/target/product/cancunf/obj/PACKAGING/target_files_intermediates/*-target_files*.zip | head -1)
    [ -n "$TF" ] || { echo "no target-files zip; build target-files-package first" >&2; exit 1; }
    id=$(unzip -p "$TF" SYSTEM/build.prop | sed -n "s/^ro.build.version.incremental=//p")
    # LineageOS keeps its version props in the product partition.
    ver=$(unzip -p "$TF" PRODUCT/etc/build.prop | sed -n "s/^ro.lineage.version=//p")
    [ -n "$ver" ] || { echo "no ro.lineage.version in PRODUCT/etc/build.prop" >&2; exit 1; }
    out=/lin/release/$id
    mkdir -p "$out"
    echo "target files: $TF (build $id)"

    # signapk and apksigner are Java; use the JDK Soong builds with (JDK 21 by default).
    export PATH=$PWD/out/host/linux-x86/bin:$PWD/prebuilts/jdk/jdk21/linux-x86/bin:$PATH
    tools="--path out/host/linux-x86"

    # Every APEX gets its own key: container with the x509 pair, payload with
    # the PEM. The names come from the build itself, so a new APEX without a
    # key fails here rather than shipping with a test key.
    apex_args=()
    for apex in $(unzip -p "$TF" META/apexkeys.txt | grep -oE "^name=\"[^\"]+\.apex\"" | sed -E "s/^name=\"(.*)\"$/\1/"); do
        k=${apex%.apex}
        [ -s "$K/$k.pem" ] || { echo "no key for $apex; run build/keys.sh" >&2; exit 1; }
        apex_args+=(--extra_apks "$apex=$K/$k" --extra_apex_payload_key "$apex=$K/$k.pem")
    done

    # LineageOS adds its official key to recovery (PRODUCT_EXTRA_RECOVERY_KEYS
    # in vendor/lineage/config/common.mk), so recovery would also install any
    # zip signed by official LineageOS. Sign from a copy without that list.
    work=$out/work
    rm -rf "$work"; mkdir -p "$work/META"
    cp "$TF" "$work/tf.zip"
    unzip -p "$TF" META/misc_info.txt | grep -v "^extra_recovery_keys=" > "$work/META/misc_info.txt"
    (cd "$work" && zip -q tf.zip META/misc_info.txt)

    signed_tf=$out/lineage_cancunf-$id-signed-target_files.zip
    sign_target_files_apks $tools -o -d "$K" "${apex_args[@]}" \
        --avb_vbmeta_key "$K/avb.pem" --avb_vbmeta_algorithm SHA256_RSA4096 \
        --avb_vbmeta_system_key "$K/avb.pem" --avb_vbmeta_system_algorithm SHA256_RSA4096 \
        "$work/tf.zip" "$signed_tf"
    rm -rf "$work"

    # Every OTA trust store must hold exactly our release certificate.
    want=$(openssl x509 -in "$K/releasekey.x509.pem" -noout -fingerprint -sha256)
    for z in $(unzip -Z1 "$signed_tf" | grep "/otacerts.zip$"); do
        unzip -p "$signed_tf" "$z" > "$out/otacerts.check.zip"
        n=$(unzip -Z1 "$out/otacerts.check.zip" | wc -l)
        got=$(unzip -p "$out/otacerts.check.zip" | openssl x509 -noout -fingerprint -sha256)
        rm -f "$out/otacerts.check.zip"
        [ "$n" = 1 ] && [ "$got" = "$want" ] || { echo "$z: expected only the release certificate, found $n entries" >&2; exit 1; }
        echo "trust store ok: $z"
    done

    ota=$out/lineage-$ver-signed.zip
    ota_from_target_files $tools -k "$K/releasekey" "$signed_tf" "$ota"
    img_from_target_files "$signed_tf" "$out/lineage_cancunf-$id-signed-img.zip"

    ( cd "$out" && sha256sum *.zip > SHA256SUMS )
    ls -la "$out"
'
