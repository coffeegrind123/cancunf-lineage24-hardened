#!/bin/bash
# Sign an Ovis APK built by .github/workflows/ovis.yml and publish it as a
# release AppSetup installs from (docs/10-appsetup.md).
#
#   gh workflow run ovis.yml -f ref=<devswha/ovis commit>   # build it in CI
#   build/ovis-publish.sh <run id>                          # sign + publish
#   DRY_RUN=1 build/ovis-publish.sh <run id>                # sign, publish nothing
#
# The CI build is unsigned. It is signed here with /lin/keys/ovis (made for
# Ovis alone, so the app holds no signature permission of the ROM's keys), and
# only when its signer matches the certificate AppSetup pins. The release is
# "ovis-v<versionName>", created with --latest=false: the ROM release stays the
# repository's latest, and publish.sh deletes only "cancunf-" releases.
set -euo pipefail

REPO=${REPO:-coffeegrind123/cancunf-lineage24-hardened}
VOL=${VOL:-lineage-build}
IMAGE=${IMAGE:-lineage-build:24}
STAGE=${STAGE:-${TMPDIR:-/tmp}/ovis-publish}
PACKAGE=sh.ovis.app
TAG_PREFIX=ovis-v
ASSET_SUFFIX=-universal.apk
# AppSetup's pin (Catalog.java OVIS_KEY): SHA-256 of the signing certificate
CERT_SHA256=a5016d9cd00b0182fbd54742b7c4081116a520747740aa93b1640f9534106f0f
here=$(dirname "$0")

run=${1:?usage: build/ovis-publish.sh <workflow run id>}
[[ $run =~ ^[0-9]+$ ]] || { echo "bad run id: $run" >&2; exit 1; }
"$here/ensure-volume.sh" >/dev/null

conclusion=$(gh run view "$run" -R "$REPO" --json conclusion,workflowName --jq '.workflowName+" "+.conclusion')
[ "$conclusion" = "Ovis APK success" ] || { echo "run $run is not a successful Ovis APK run: $conclusion" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/in" "$STAGE/out"
gh run download "$run" -R "$REPO" -n ovis-unsigned -D "$STAGE/in"

meta=$STAGE/in/ovis-build.json
apk=$STAGE/in/ovis-unsigned.apk
pkg=$(jq -r .package "$meta")
version=$(jq -r .versionName "$meta")
code=$(jq -r .versionCode "$meta")
source=$(jq -r .source "$meta")
[ "$pkg" = "$PACKAGE" ] || { echo "package is '$pkg', not $PACKAGE" >&2; exit 1; }
[[ $version =~ ^[0-9][0-9A-Za-z.+-]*$ ]] || { echo "bad versionName: $version" >&2; exit 1; }
[[ $code =~ ^[0-9]+$ ]] || { echo "bad versionCode: $code" >&2; exit 1; }
[[ $source =~ ^[0-9a-f]{40}$ ]] || { echo "bad source commit: $source" >&2; exit 1; }
[ "$(sha256sum "$apk" | cut -d' ' -f1)" = "$(jq -r .unsigned_sha256 "$meta")" ] \
    || { echo "the downloaded APK does not match the hash CI recorded" >&2; exit 1; }

tag=$TAG_PREFIX$version
name=ovis-$version$ASSET_SUFFIX
if gh release view "$tag" -R "$REPO" >/dev/null 2>&1; then
    echo "release $tag exists; AppSetup compares version names, so a rebuild of the same version would never install" >&2
    exit 1
fi

# Align (16 KiB for uncompressed native libraries, 4 for the rest), sign with
# v2 and v3 (minSdk 26 needs no v1), then verify and print the signer.
tar -C "$STAGE/in" -cf - ovis-unsigned.apk | docker run --rm -i -v "$VOL":/lin "$IMAGE" bash -c '
    set -euo pipefail
    bin=/lin/src/out/host/linux-x86/bin
    java=$(ls -d /lin/src/prebuilts/jdk/jdk*/linux-x86 | sort -V | tail -1)/bin/java
    signer() { "$java" -jar /lin/src/prebuilts/sdk/tools/linux/lib/apksigner.jar "$@"; }
    w=$(mktemp -d)
    tar -C "$w" -xf -
    if ! "$bin/zipalign" -c -P 16 4 "$w/ovis-unsigned.apk" >/dev/null; then
        "$bin/zipalign" -P 16 -f 4 "$w/ovis-unsigned.apk" "$w/aligned.apk"
        mv "$w/aligned.apk" "$w/ovis-unsigned.apk"
    fi
    signer sign --key /lin/keys/ovis.pk8 --cert /lin/keys/ovis.x509.pem \
        --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true \
        --out "$w/ovis.apk" "$w/ovis-unsigned.apk"
    signer verify --verbose --print-certs "$w/ovis.apk" > "$w/verify.txt"
    tar -C "$w" -cf - ovis.apk verify.txt
' | tar -C "$STAGE/out" -xf -

cat "$STAGE/out/verify.txt"
signed=$STAGE/out/$name
mv "$STAGE/out/ovis.apk" "$signed"
grep -q '^Verified using v2 scheme (APK Signature Scheme v2): true$' "$STAGE/out/verify.txt" \
    || { echo "the signed APK has no verified v2 signature" >&2; exit 1; }
[ "$(grep -c '^Signer #[0-9]* certificate SHA-256 digest: ' "$STAGE/out/verify.txt")" = 1 ] \
    || { echo "the signed APK does not have exactly one signer" >&2; exit 1; }
cert=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$STAGE/out/verify.txt")
[ "$cert" = "$CERT_SHA256" ] || { echo "signer is '$cert', AppSetup pins $CERT_SHA256" >&2; exit 1; }
sha=$(sha256sum "$signed" | cut -d' ' -f1)
jq --arg sha "$sha" --arg cert "$cert" --arg asset "$name" \
    '. + {asset:$asset, sha256:$sha, signer_sha256:$cert}' "$meta" > "$STAGE/out/ovis-build.json"
cat "$STAGE/out/ovis-build.json"

if [ -n "${DRY_RUN:-}" ]; then
    echo "DRY_RUN: signed $signed; nothing published"
    exit 0
fi

notes="Ovis $version (versionCode $code), the Android app of [devswha/ovis](https://github.com/devswha/ovis) (MIT), built from commit [\`${source:0:12}\`](https://github.com/devswha/ovis/commit/$source) by [this workflow run]($(jq -r .run "$meta")).

Signed by us, not by the Ovis project: certificate SHA-256 \`$cert\`. AppSetup installs it only with that signer. FCM push is unavailable in this build: it carries no Firebase configuration.

SHA-256 of \`$name\`: \`$sha\`"
gh release create "$tag" -R "$REPO" --latest=false --target main \
    --title "Ovis $version (Android, built from source)" --notes "$notes" \
    "$signed" "$STAGE/out/ovis-build.json"

remote=$(gh api "repos/$REPO/releases/tags/$tag" --jq ".assets[] | select(.name==\"$name\") | .digest")
[ "$remote" = "sha256:$sha" ] || { echo "uploaded $name reads back as '$remote', expected sha256:$sha" >&2; exit 1; }
echo "published $tag: $name sha256 $sha"
