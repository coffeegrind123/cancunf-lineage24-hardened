#!/usr/bin/env python3
"""Check that every class and method a GmsCompatConfig names exists in the tree.

GmsCompat parses its config strictly on non-user builds: a single class it
cannot load rejects the whole config, and GmsCompat cannot start. GrapheneOS's
config can name GrapheneOS-only framework classes, so run this after every
GmsCompatConfig update (docs/06-gmscompat-port.md).

Runs in the build container:
  gmscompat-config-check.py [config.apk]   (default: external/GmsCompatConfig)
Exit status 1 if anything is missing.
"""
import os
import re
import subprocess
import sys
import zipfile

SRC = os.environ.get("SRC", "/lin/src")
ROOTS = ["frameworks/base", "packages/modules", "frameworks/opt/telephony"]


def load_config(apk):
    with zipfile.ZipFile(apk) as z:
        return z.read("gmscompat_config").decode().splitlines()


def stub_sections(lines):
    """{class: {method, ...}} from every [[stubs*]] section."""
    want, section, cls = {}, None, None
    for line in lines:
        if line.startswith("[["):
            section, cls = line.strip("[]"), None
            continue
        if not section or not section.startswith("stubs"):
            continue
        if line.startswith("[") and line.endswith("]"):
            cls = line.strip("[]")
            want.setdefault(cls, set())
            continue
        if cls and line.strip() and not line.startswith("#"):
            want[cls].add(line.split()[0])
    return want


def main():
    os.chdir(SRC)
    apk = sys.argv[1] if len(sys.argv) > 1 else "external/GmsCompatConfig/prebuilt/app-release.apk"
    want = stub_sections(load_config(apk))

    found = subprocess.run(
        ["find", *ROOTS, "-name", "*.java", "-path", "*/java/*"],
        capture_output=True, text=True).stdout.split()
    by_name = {}
    for path in found:
        by_name.setdefault(os.path.basename(path)[:-5], []).append(path)

    missing = 0
    for cls, methods in sorted(want.items()):
        outer = cls.split("$")[0]
        rel = outer.replace(".", "/") + ".java"
        files = [p for p in by_name.get(outer.rsplit(".", 1)[-1], []) if p.endswith(rel)]
        if not files:
            print(f"MISSING CLASS {cls}")
            missing += 1
            continue
        src = "".join(open(f, errors="replace").read() for f in files)
        for m in sorted(methods):
            if not re.search(r"\b" + re.escape(m) + r"\s*\(", src):
                print(f"MISSING METHOD {cls}.{m}")
                missing += 1

    print(f"checked {len(want)} classes, {sum(len(v) for v in want.values())} methods, {missing} missing")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
