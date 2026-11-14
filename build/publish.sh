#!/bin/bash
# Publish a signed release: GitHub release with the OTA, then the Updater feed.
#
#   build/publish.sh                 # newest /lin/release/<build id>/
#   build/publish.sh 1794655118      # a specific build
#   DRY_RUN=1 build/publish.sh       # stage and print, publish nothing
#
# The repository keeps only the latest release:
#   1. create release <tag> with the OTA zip and verify the upload,
#   2. force-push ota.json to the "ota" branch (the Updater's feed),
#   3. delete every older release and its tag.
# The order matters: the feed never points at a deleted file.
#
# The feed lives on raw.githubusercontent.com because the Updater fetches it
# without following redirects; releases/latest/download/... is a redirect.
# The OTA itself may redirect once (github.com -> release-assets), which the
# Updater's downloader follows.
#
# The signed target files stay on the build disk: incrementals need them.
set -euo pipefail

REPO=${REPO:-coffeegrind123/cancunf-lineage24-hardened}
FEED_BRANCH=${FEED_BRANCH:-ota}
FEED_FILE=ota.json
TAG_PREFIX=cancunf-
VOL=${VOL:-lineage-build}
IMAGE=${IMAGE:-lineage-build:24}
STAGE=${STAGE:-$HOME/.cache/cancunf-publish}

"$(dirname "$0")/ensure-volume.sh" >/dev/null

id=${1:-$(docker run --rm -v "$VOL":/lin "$IMAGE" bash -c \
    'ls -1 /lin/release | grep -E "^[0-9]+$" | sort -n | tail -1')}
[[ $id =~ ^[0-9]+$ ]] || { echo "bad build id: $id" >&2; exit 1; }
tag=$TAG_PREFIX$id

# Facts about the build, read from the signed package itself.
meta=$(docker run --rm -v "$VOL":/lin -e ID="$id" "$IMAGE" bash -c '
    set -euo pipefail
    d=/lin/release/$ID
    ota=$(ls "$d"/lineage-*-signed.zip | head -1)
    tf=$d/lineage_cancunf-$ID-signed-target_files.zip
    sys=$(unzip -p "$tf" SYSTEM/build.prop)
    prod=$(unzip -p "$tf" PRODUCT/etc/build.prop)
    p() { echo "$1" | sed -n "s/^$2=//p" | head -1; }
    echo "OTA_PATH=$ota"
    echo "OTA_NAME=$(basename "$ota")"
    echo "OTA_SIZE=$(stat -c %s "$ota")"
    echo "OTA_SHA256=$(sha256sum "$ota" | cut -d" " -f1)"
    echo "DATETIME=$(p "$sys" ro.build.date.utc)"
    echo "SDK=$(p "$sys" ro.build.version.sdk)"
    echo "PATCH=$(p "$sys" ro.build.version.security_patch)"
    echo "TYPE=$(p "$prod" ro.lineage.releasetype)"
    echo "VERSION=$(p "$prod" ro.lineage.build.version)"
    echo "TAGS=$(p "$sys" ro.build.tags)"
')
eval "$meta"
for v in OTA_NAME OTA_SIZE OTA_SHA256 DATETIME SDK PATCH TYPE VERSION; do
    [ -n "${!v}" ] || { echo "could not read $v from build $id" >&2; exit 1; }
done
[ "$TAGS" = release-keys ] || { echo "build $id is not release-signed (ro.build.tags=$TAGS)" >&2; exit 1; }

url=https://github.com/$REPO/releases/download/$tag/$OTA_NAME
json=$(python3 -I -c '
import json, sys
d, sdk, patch, typ, ver, name, sha, size, url = sys.argv[1:]
print(json.dumps([{
    "datetime": int(d), "type": typ, "version": ver,
    "files": [{"filename": name, "sha256": sha, "size": int(size), "url": url,
               "os_sdk_level": int(sdk), "os_patch_level": patch}],
}], indent=2))
' "$DATETIME" "$SDK" "$PATCH" "$TYPE" "$VERSION" "$OTA_NAME" "$OTA_SHA256" "$OTA_SIZE" "$url")

echo "build $id -> release $tag"
echo "$json"
if [ -n "${DRY_RUN:-}" ]; then
    echo "DRY_RUN: nothing published"
    exit 0
fi

# 1. Release. gh needs a local file, so stage the OTA out of the build volume.
mkdir -p "$STAGE"
staged=$STAGE/$OTA_NAME
docker run --rm -v "$VOL":/lin -e P="$OTA_PATH" "$IMAGE" bash -c 'cat "$P"' > "$staged"
[ "$(sha256sum "$staged" | cut -d' ' -f1)" = "$OTA_SHA256" ] || { echo "staged copy does not match" >&2; exit 1; }

if gh release view "$tag" -R "$REPO" >/dev/null 2>&1; then
    echo "release $tag already exists" >&2; exit 1
fi
gh release create "$tag" -R "$REPO" --title "LineageOS $VERSION for cancunf ($id)" \
    --notes "Signed OTA for the moto g54 5G (cancunf). Install with the Updater, or from recovery.

- Build: \`$id\`, Android SDK $SDK, security patch $PATCH
- SHA-256: \`$OTA_SHA256\`" "$staged"
rm -f "$staged"

remote=$(gh api "repos/$REPO/releases/tags/$tag" --jq ".assets[] | select(.name==\"$OTA_NAME\") | \"\(.size) \(.digest)\"")
[ "$remote" = "$OTA_SIZE sha256:$OTA_SHA256" ] || { echo "uploaded asset does not match: $remote" >&2; exit 1; }
echo "release asset verified"

# 2. Feed: a single-commit branch holding only cancunf.json.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q -b "$FEED_BRANCH"
git -C "$work" config core.hooksPath "$(git -C "$(dirname "$0")" config core.hooksPath || true)"
echo "$json" > "$work/$FEED_FILE"
git -C "$work" add "$FEED_FILE"
git -C "$work" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
    commit -q -m "ota: $tag"
git -C "$work" push -q -f "https://github.com/$REPO.git" "$FEED_BRANCH:$FEED_BRANCH"

feed=https://raw.githubusercontent.com/$REPO/$FEED_BRANCH/$FEED_FILE
for i in $(seq 1 30); do
    got=$(curl -fsS -H 'Cache-Control: no-cache' "$feed?nocache=$RANDOM" || true)
    [ "$got" = "$json" ] && break
    sleep 10
done
[ "$got" = "$json" ] || { echo "feed at $feed does not show the new build yet" >&2; exit 1; }
echo "feed verified: $feed"

# 3. Only the latest release stays.
for old in $(gh release list -R "$REPO" --limit 100 --json tagName --jq '.[].tagName' | grep "^$TAG_PREFIX" | grep -vx "$tag"); do
    gh release delete "$old" -R "$REPO" --yes --cleanup-tag
    echo "deleted old release $old"
done
