#!/bin/bash
# Publish a signed release: GitHub release with the OTAs, then the Updater feed.
#
#   build/publish.sh                 # newest /lin/release/<build id>/
#   build/publish.sh 1794655118      # a specific build
#   DRY_RUN=1 build/publish.sh       # make the incrementals, print the feed, publish nothing
#   INCR_SOURCES=3                   # how many older builds get an incremental
#
# The repository keeps only the latest release:
#   1. create release <tag> with the full OTA plus one incremental per recent
#      older build, and verify every upload,
#   2. force-push the feed files to the "ota" branch,
#   3. delete every older release and its tag.
# The order matters: the feed never points at a deleted file.
#
# Feed layout (branch "ota"):
#   feed.json   read by every build after 1794905814 (device patch 0018): the
#               full OTA plus every incremental; the Updater (patch 0001) keeps
#               the entries for the running build.
#   <id>.json   read by builds after 1794688012 through 1794905814 ({incr} URI);
#               the Updater puts ro.build.version.incremental, which is our
#               build id, into the URL. Recent builds get an incremental,
#               older ones the full OTA, and the new build itself gets [].
#   ota.json    the full OTA, for builds up to 1794688012 whose feed URI was
#               fixed at ota/ota.json.
# Every build in /lin/release with signed target files gets a file: an {incr}
# build without one gets HTTP 404, which the Updater shows as an error.
#
# The feed lives on raw.githubusercontent.com because the Updater fetches it
# without following redirects; releases/latest/download/... is a redirect.
# The OTAs may redirect once (github.com -> release-assets), which the
# Updater's downloader and update_engine both follow, range requests included.
# ota_property_files lets the Updater stream the payload into update_engine
# instead of downloading the zip to /data first.
#
# The signed target files stay on the build disk: incrementals need them.
set -euo pipefail

REPO=${REPO:-coffeegrind123/cancunf-lineage24-hardened}
FEED_BRANCH=${FEED_BRANCH:-ota}
LEGACY_FEED=ota.json
TAG_PREFIX=cancunf-
INCR_SOURCES=${INCR_SOURCES:-3}
VOL=${VOL:-lineage-build}
IMAGE=${IMAGE:-lineage-build:24}
# Staging stays off the 9p mount of the Windows home: a 1.7 GB write there
# failed with ENOMEM under memory pressure (2026-11-15).
STAGE=${STAGE:-${TMPDIR:-/tmp}/cancunf-publish}
here=$(dirname "$0")

[[ $INCR_SOURCES =~ ^[0-9]+$ ]] || { echo "bad INCR_SOURCES: $INCR_SOURCES" >&2; exit 1; }
"$here/ensure-volume.sh" >/dev/null

vol() { docker run --rm -v "$VOL":/lin "$@"; }

id=${1:-$(vol "$IMAGE" bash -c 'ls -1 /lin/release | grep -E "^[0-9]+$" | sort -n | tail -1')}
[[ $id =~ ^[0-9]+$ ]] || { echo "bad build id: $id" >&2; exit 1; }
tag=$TAG_PREFIX$id

# Older builds that could be on a phone: every one with signed target files.
mapfile -t sources < <(vol -e ID="$id" "$IMAGE" bash -c '
    for d in /lin/release/*/; do
        s=$(basename "$d")
        [[ $s =~ ^[0-9]+$ ]] && [ "$s" -lt "$ID" ] || continue
        [ -s "$d/lineage_cancunf-$s-signed-target_files.zip" ] && echo "$s"
    done | sort -rn')
incr=("${sources[@]:0:$INCR_SOURCES}")
echo "build $id; older builds: ${sources[*]:-none}; incrementals from: ${incr[*]:-none}"

for s in "${incr[@]}"; do
    "$here/incremental.sh" "$s" "$id"
done

# Facts about the build and every package, read from the packages themselves.
# One JSON object per line: the build first, then each OTA.
facts=$(vol -e ID="$id" "$IMAGE" bash -c '
    set -euo pipefail
    d=/lin/release/$ID
    tf=$d/lineage_cancunf-$ID-signed-target_files.zip
    sys=$(unzip -p "$tf" SYSTEM/build.prop)
    prod=$(unzip -p "$tf" PRODUCT/etc/build.prop)
    p() { echo "$1" | sed -n "s/^$2=//p" | head -1; }
    printf "{\"kind\":\"build\",\"datetime\":\"%s\",\"sdk\":\"%s\",\"patch\":\"%s\",\"type\":\"%s\",\"version\":\"%s\",\"tags\":\"%s\"}\n" \
        "$(p "$sys" ro.build.date.utc)" "$(p "$sys" ro.build.version.sdk)" \
        "$(p "$sys" ro.build.version.security_patch)" "$(p "$prod" ro.lineage.releasetype)" \
        "$(p "$prod" ro.lineage.build.version)" "$(p "$sys" ro.build.tags)"
    for z in "$d"/lineage-*-signed.zip; do
        m=$(unzip -p "$z" META-INF/com/android/metadata)
        printf "{\"kind\":\"ota\",\"path\":\"%s\",\"name\":\"%s\",\"size\":%s,\"sha256\":\"%s\",\"pre\":\"%s\",\"post\":\"%s\",\"ab\":\"%s\",\"props\":\"%s\"}\n" \
            "$z" "$(basename "$z")" "$(stat -c %s "$z")" "$(sha256sum "$z" | cut -d" " -f1)" \
            "$(p "$m" pre-build-incremental)" "$(p "$m" post-build-incremental)" \
            "$(p "$m" ota-type)" "$(p "$m" ota-property-files | tr -d " ")"
    done
')

# Build the feed files and the upload list (path, name, size, sha256); every
# check that can fail before anything is published happens in feed.py.
work=$(mktemp -d)
staged=()
trap 'rm -rf "$work"; rm -f "${staged[@]}"' EXIT
feed=$work/feed
mkdir "$feed"
assets=$(python3 -I "$here/feed.py" "$feed" "$REPO" "$tag" "$id" "$LEGACY_FEED" \
    "${sources[*]}" "${incr[*]}" <<<"$facts")

echo "release $tag:"
cut -f2,3 <<<"$assets"
for f in "$feed"/*.json; do
    echo "--- $(basename "$f")"
    cat "$f"
done
if [ -n "${DRY_RUN:-}" ]; then
    echo "DRY_RUN: nothing published"
    exit 0
fi

if gh release view "$tag" -R "$REPO" >/dev/null 2>&1; then
    echo "release $tag already exists" >&2; exit 1
fi

# 1. Release. gh needs local files, so stage the OTAs out of the build volume.
mkdir -p "$STAGE"
while IFS=$'\t' read -r path name size sha; do
    s=$STAGE/$name
    staged+=("$s")
    vol -e P="$path" "$IMAGE" bash -c 'cat "$P"' > "$s"
    [ "$(sha256sum "$s" | cut -d' ' -f1)" = "$sha" ] || { echo "staged $name does not match" >&2; exit 1; }
done <<<"$assets"

build_line=$(head -1 <<<"$facts")
field() { python3 -I -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$build_line" "$1"; }
version=$(field version); sdk=$(field sdk); patch=$(field patch)
sums=$(awk -F'\t' '{ printf "- `%s`: `%s`\n", $2, $4 }' <<<"$assets")

gh release create "$tag" -R "$REPO" --title "LineageOS $version for cancunf ($id)" \
    --notes "Signed OTAs for the moto g54 5G (cancunf). Install with the Updater, or the full OTA from recovery. An \`-incr-<build>\` package updates only from that build.

- Build: \`$id\`, Android SDK $sdk, security patch $patch

SHA-256:
$sums" "${staged[@]}"
rm -f "${staged[@]}"
staged=()

while IFS=$'\t' read -r path name size sha; do
    remote=$(gh api "repos/$REPO/releases/tags/$tag" --jq ".assets[] | select(.name==\"$name\") | \"\(.size) \(.digest)\"")
    [ "$remote" = "$size sha256:$sha" ] || { echo "uploaded $name does not match: $remote" >&2; exit 1; }
    echo "verified asset $name"
done <<<"$assets"

# 2. Feed: a single-commit branch holding only the feed files.
repo=$work/repo
git init -q -b "$FEED_BRANCH" "$repo"
git -C "$repo" config core.hooksPath "$(git -C "$here" config core.hooksPath || true)"
cp "$feed"/*.json "$repo/"
git -C "$repo" add -A
git -C "$repo" -c user.name="$(git -C "$here" config user.name)" -c user.email="$(git -C "$here" config user.email)" \
    commit -q -m "ota: $tag"
git -C "$repo" push -q -f "https://github.com/$REPO.git" "$FEED_BRANCH:$FEED_BRANCH"

# raw.githubusercontent caches for a few minutes; wait until every file is live.
for f in "$feed"/*.json; do
    u=https://raw.githubusercontent.com/$REPO/$FEED_BRANCH/$(basename "$f")
    ok=
    for i in $(seq 1 30); do
        if curl -fsS -H 'Cache-Control: no-cache' "$u?nocache=$RANDOM" | cmp -s - "$f"; then
            ok=1; break
        fi
        sleep 10
    done
    [ -n "$ok" ] || { echo "feed $u does not show the new build yet" >&2; exit 1; }
    echo "feed verified: $u"
done

# 3. Only the latest release stays.
for old in $(gh release list -R "$REPO" --limit 100 --json tagName --jq '.[].tagName' | grep "^$TAG_PREFIX" | grep -vx "$tag"); do
    gh release delete "$old" -R "$REPO" --yes --cleanup-tag
    echo "deleted old release $old"
done
