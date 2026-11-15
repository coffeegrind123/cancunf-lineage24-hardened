#!/usr/bin/env python3
"""Write the Updater feed files for one release; called by build/publish.sh.

    feed.py <out dir> <repo> <tag> <build id> <legacy feed name>
            "<older build ids>" "<ids that get an incremental>" < facts

stdin holds one JSON object per line: the build ({"kind": "build"}) and then
every OTA package in its release directory ({"kind": "ota"}). Writes
<out dir>/<id>.json for every older build and for the build itself, plus the
legacy feed, and prints the package paths to upload, one per line.

The feed format is the LineageOS Updater's (NetworkUpdate.kt): a list of
updates, each with one file; the Updater reads only files[0].
"""
import json
import os
import sys

# Payload ranges the Updater needs to stream an A/B update (Constants.java).
STREAM_ENTRIES = ("payload_metadata.bin", "payload.bin", "payload_properties.txt")
RELEASE_KEYS = "release-keys"


def fail(msg):
    sys.exit(f"feed.py: {msg}")


def stream_ranges(props, name):
    """Check ota-property-files has the entries streaming needs, as name:offset:size."""
    have = {}
    for token in filter(None, props.split(",")):
        parts = token.split(":")
        if len(parts) != 3 or not parts[1].isdigit() or not parts[2].isdigit():
            fail(f"{name}: malformed ota-property-files entry {token!r}")
        have[parts[0]] = parts
    missing = [e for e in STREAM_ENTRIES if e not in have]
    if missing:
        fail(f"{name}: ota-property-files lacks {', '.join(missing)}")
    return props


def entry(build, ota, url):
    file = {
        "filename": ota["name"],
        "sha256": ota["sha256"],
        "size": ota["size"],
        "url": url,
        "os_sdk_level": int(build["sdk"]),
        "os_patch_level": build["patch"],
        "ota_property_files": ota["props"],
    }
    # Our Updater patch labels an entry incremental, and blocks it on any
    # other installed build, when this is set. Stock Updaters ignore it.
    if ota["pre"]:
        file["pre_build_incremental"] = ota["pre"]
    return [{
        "datetime": int(build["datetime"]),
        "type": build["type"],
        "version": build["version"],
        "files": [file],
    }]


def main():
    out, repo, tag, bid, legacy, older, incr = sys.argv[1:8]
    older, incr = older.split(), incr.split()

    facts = [json.loads(line) for line in sys.stdin if line.strip()]
    builds = [f for f in facts if f["kind"] == "build"]
    if len(builds) != 1:
        fail(f"expected one build record, got {len(builds)}")
    build = builds[0]
    for k in ("datetime", "sdk", "patch", "type", "version"):
        if not build[k]:
            fail(f"could not read {k} from build {bid}")
    if build["tags"] != RELEASE_KEYS:
        fail(f"build {bid} is not release-signed (ro.build.tags={build['tags']})")

    full, incrementals = None, {}
    for ota in (f for f in facts if f["kind"] == "ota"):
        if ota["ab"] != "AB" or ota["post"] != bid:
            fail(f"{ota['name']}: ota-type={ota['ab']} post-build-incremental={ota['post']}, "
                 f"expected AB and {bid}")
        stream_ranges(ota["props"], ota["name"])
        if not ota["pre"]:
            if full:
                fail(f"two full OTAs: {full['name']}, {ota['name']}")
            full = ota
        elif ota["pre"] in incr:
            incrementals[ota["pre"]] = ota
    if not full:
        fail(f"no full OTA for build {bid}")
    missing = [s for s in incr if s not in incrementals]
    if missing:
        fail(f"no incremental from {', '.join(missing)}")

    names = [full["name"]] + [o["name"] for o in incrementals.values()]
    if len(set(names)) != len(names):
        fail(f"duplicate asset names: {names}")

    def url(ota):
        return f"https://github.com/{repo}/releases/download/{tag}/{ota['name']}"

    feeds = {legacy: entry(build, full, url(full)), f"{bid}.json": []}
    for s in older:
        ota = incrementals.get(s, full)
        feeds[f"{s}.json"] = entry(build, ota, url(ota))

    for name, body in feeds.items():
        with open(os.path.join(out, name), "w") as fh:
            json.dump(body, fh, indent=2)
            fh.write("\n")
        target = body[0]["files"][0]["filename"] if body else "(no update)"
        print(f"feed {name} -> {target}", file=sys.stderr)

    for ota in [full, *incrementals.values()]:
        print(f"{ota['path']}\t{ota['name']}\t{ota['size']}\t{ota['sha256']}")


main()
