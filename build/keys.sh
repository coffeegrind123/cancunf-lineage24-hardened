#!/bin/bash
# Generate this project's release keys, once, on the build volume.
#
#   build/keys.sh
#
# Keys go to /lin/keys (mode 700) and never into this repo. Losing them means
# installed phones can't take our updates; leaking them lets anyone sign updates
# the phones accept (docs/07-maintenance.md). Back the directory up offline,
# encrypted, straight after generating it.
#
# The script refuses to touch an existing key, so re-running only fills gaps,
# such as an APEX that a newer build added.
set -euo pipefail

VOL=${VOL:-lineage-build}
IMAGE=${IMAGE:-lineage-build:24}
# Embedded in every certificate and visible to anyone holding a build: project
# name only, nothing personal.
SUBJECT=${SUBJECT:-/O=cancunf-lineage24-hardened/OU=Release/CN=cancunf-lineage24-hardened}

"$(dirname "$0")/ensure-volume.sh"

docker run --rm -e SUBJECT="$SUBJECT" -v "$VOL":/lin "$IMAGE" bash -c '
    set -euo pipefail
    K=/lin/keys
    S=/lin/src
    mkdir -p "$K"
    chmod 700 "$K"
    umask 077

    # make_key asks for a password on stdin; blank means an unencrypted key,
    # protected by the directory mode and the offline encrypted backup.
    mk() {
        local name=$1 maker=$2
        if [ -e "$K/$name.pk8" ]; then
            echo "keep   $name"
            return
        fi
        echo | "$maker" "$K/$name" "$SUBJECT" >/dev/null 2>&1 || true
        [ -s "$K/$name.pk8" ] && [ -s "$K/$name.x509.pem" ] || { echo "FAILED $name" >&2; exit 1; }
        echo "new    $name"
    }

    # APK and platform certificates: the set the LineageOS signing guide uses,
    # plus gmscompat_lib for the GmsCompat port (docs/06-gmscompat-port.md).
    for cert in bluetooth cyngn-app media networkstack nfc platform releasekey \
                sdk_sandbox shared testcert testkey verity gmscompat_lib; do
        mk "$cert" "$S/development/tools/make_key"
    done

    # One 4096-bit key per APEX: the container is signed with the x509 pair,
    # the payload with the PEM form of the same key.
    sed "s/2048/4096/g" "$S/development/tools/make_key" > "$K/.make_key_4096"
    chmod 700 "$K/.make_key_4096"
    T=$S/out/target/product/cancunf/obj/PACKAGING/target_files_intermediates/lineage_cancunf-target_files
    for apex in $(grep -oE "^name=\"[^\"]+\.apex\"" "$T/META/apexkeys.txt" | sed -E "s/^name=\"(.*)\.apex\"$/\1/"); do
        mk "$apex" "$K/.make_key_4096"
        [ -e "$K/$apex.pem" ] || openssl pkcs8 -in "$K/$apex.pk8" -inform DER -nocrypt -out "$K/$apex.pem"
    done
    rm -f "$K/.make_key_4096"

    # AVB: one RSA-4096 key for vbmeta and vbmeta_system. avb_pkmd.bin is its
    # public half, for bootloaders that accept a custom AVB key.
    if [ ! -e "$K/avb.pem" ]; then
        openssl genrsa -out "$K/avb.pem" 4096 2>/dev/null
        echo "new    avb"
    else
        echo "keep   avb"
    fi
    [ -e "$K/avb_pkmd.bin" ] || "$S/external/avb/avbtool.py" extract_public_key --key "$K/avb.pem" --output "$K/avb_pkmd.bin"

    chmod -R go-rwx "$K"
    echo "$(ls "$K" | wc -l) files in $K, $(stat -c %a "$K") $(stat -c %U "$K")"
'
