# Maintenance: security updates, re-porting, OTA releases

The goal is a fresh, signed update every few months, or monthly when wanted. It is built from current sources, with GrapheneOS's changes re-ported, published as a GitHub release, and installed on the phone over the air.

## What gets security fixes, and from where

GrapheneOS ships almost weekly. Each release combines:
1. AOSP's monthly security patches
2. GrapheneOS's own fixes and hardening
3. Pixel firmware, driver and kernel updates
4. Vanadium updates

On this phone each layer has a different source and cadence:

| Layer | Source of fixes | How we get them |
|---|---|---|
| Android framework and system | LineageOS merges the monthly ASB into `lineage-24.0` | `repo sync` + rebuild. Monthly at best, and only when we release. |
| Ported GrapheneOS code (GmsCompat, hardening) | GrapheneOS `17` branches | Re-port at each release (below). GmsCompat commits landed weekly through October 2026. |
| Browser (Titanium) | Its author, every few days | Independent of the ROM, because it updates itself. The preload just has to keep the author's signature. |
| Kernel | Our fork [kernel_motorola_cancunf](https://github.com/coffeegrind123/kernel_motorola_cancunf) (DragonHeart base) | Each release: merge Google `android12-5.10` (security fixes plus 5.10 stable), DragonHeart's device commits, and GrapheneOS's hardening as it applies. See [08-kernel.md](08-kernel.md). Upstream 5.10 is maintained (5.10.274 on 2026-11-06); its end-of-life date is to be checked each cycle. |
| Vendor blobs (MediaTek and Motorola HALs, IMS, drivers) | Motorola firmware, currently `V1TDS35H.83-20-5-11` (Android 15), according to the header of `proprietary-files.txt` | Only when Motorola ships newer firmware and the blobs are re-extracted. |
| Firmware (preloader, lk, tee, gz, md1img modem, scp, sspm, ...) | Same Motorola build. The tree ships these images in `vendor/motorola/cancunf/radio/` and lists them in `AB_OTA_PARTITIONS` | **Every OTA flashes them.** Newer Motorola firmware reaches the phone through our own OTA once re-extracted. |

So the framework layer can track monthly patches. The kernel, vendor and firmware layers move only as fast as Motorola and the kernel maintainer, which is well behind a Pixel running GrapheneOS. The "Android security patch" date in Settings reflects only the framework layer.

**Never flash or accept stock firmware newer than the blobs.** According to PixelOS's install guide, stock `V1TDS35H.83-20-5-14` (and `V1TDS35H.83-20-5-8-2-1-3` in Brazil) raises anti-rollback again, after which flashing ROMs built on older firmware **hardbricks the phone**. Turn off stock system updates before unlocking, and never ship firmware in our OTA beyond what the vendor blobs were extracted from. Before adopting newer Motorola firmware, check its anti-rollback values against what every installed phone runs.

**First install and anti-rollback.** Because the OTA carries Android 15 firmware, the first install moves the bootloader chain from the stock Android 14 `12-7-6` firmware to Android 15. This raises anti-rollback, so restoring a `12-7-6` backup exactly becomes impossible afterwards. Restoring to stock is still possible, to Android 15 stock firmware. PixelOS confirms the ROM zip itself is the firmware step: no separate stock Android 15 flash is needed. A phone on firmware older than `U1TDS34.94-12-7-5` must flash the first build twice so both slots get post-ARB firmware. Per-device partitions (IMEI, calibration) are not touched by the firmware images.

## Release keys

OTA updates only work if every release is signed with the **same keys** as the installed build:
- platform, shared, media, networkstack and others (`sign_target_files_apks`)
- the OTA key
- the AVB key
- the `gmscompat_lib` key

- **Generated 2026-11-12** with [`build/keys.sh`](../build/keys.sh). It writes `development/tools/make_key` certificates (bluetooth, cyngn-app, media, networkstack, nfc, platform, releasekey, sdk_sandbox, shared, testcert, testkey, verity, gmscompat_lib), one RSA-4096 key per APEX in the build, and an RSA-4096 AVB key with its `avb_pkmd.bin`. The certificate subject carries the project name only. Re-running it never overwrites a key; it only adds keys for new APEXes.
- **Never commit them.** They live on the build disk (`/lin/keys`, mode 700), with an offline encrypted backup kept by the owner.
- [`build/sign.sh`](../build/sign.sh) re-signs a finished build without recompiling. It writes three files to `/lin/release/<build id>/`: the signed target files (kept, because incrementals need them), the release OTA and the fastboot images.
  - Verified on the first release:
    - Settings is on our platform key, Etar and Launcher on releasekey, Dialer on shared.
    - APEX containers and payloads are on their own keys.
    - `vbmeta`/`vbmeta_system` are signed with our AVB key (SHA256_RSA4096).
    - `otacerts.zip` holds only our releasekey.
    - The build tags read `release-keys`.
  - `META/apkcerts.txt` and `META/apexkeys.txt` are copied through unchanged, so check real signatures, not those files.
- Motorola's bootloader does not take a custom AVB key, so the bootloader stays unlocked and AVB does not enforce our key. Signing with it still keeps `vbmeta` consistent across our releases.
- **Losing them** means the installed phone can't take our updates and needs a clean flash with userdata wiped.
- **Leaking them** means someone else can sign updates the phone will accept.
- Development builds use test keys and are never published as OTAs.

## The update procedure (every few months)

Run by the agent, after the owner approves the build:

1. **Prepare.** Re-attach the build disk if needed (`scripts/windows/attach-build-disk.ps1`), then run `build/ensure-volume.sh`.
2. **Sync.** Run `repo sync` (`build/sync.sh`). Record the new LineageOS security patch level (`PLATFORM_SECURITY_PATCH` in `build/release/` or `build/make/core/version_defaults.mk`).
3. **Check what changed upstream**, and note each item in the release notes:
   - `yaap/device_motorola_cancunf@seventeen`: new commits since the last release. Read them before building.
   - The firmware version in the header of `proprietary-files.txt`. A change means new vendor blobs and firmware. **Read its `signing-info.txt` anti-rollback values before publishing**, because an increase is permanent for every installed phone.
   - The kernel: merge Google `android12-5.10`, pick up DragonHeart's new commits, and re-check GrapheneOS's kernel hardening ([08-kernel.md](08-kernel.md)). Then build our kernel and refresh our prebuilts.
   - Whether our `patches/` still apply: `build/apply-patches.sh`, where a conflict stops the run.
4. **Re-port GrapheneOS.** For each repo in [06-gmscompat-port.md](06-gmscompat-port.md), list GrapheneOS's new commits since the last ported head recorded in [`ported.json`](../ported.json):
   - Follow-ups and `fixup!`s of ported features: cherry-pick them.
   - Reverts: apply them.
   - New hardening: judge each one against this hardware (Pixel-only changes are skipped).
   - If GrapheneOS rebased onto a new AOSP tag (`android-17.0.0_rN`), re-check the base with the same `ls-remote` method used in the survey.
   - Update `ported.json` with the new heads.
   - Run `build/gmscompat-config-check.py` in the build container. Every class and method the synced GmsCompatConfig names must exist, or GmsCompat rejects its config on our userdebug build and can't start ([06-gmscompat-port.md](06-gmscompat-port.md)).
5. **Build and sign.**
   - `build/zram.sh on` (after any VM restart; check with `build/zram.sh status`).
   - `TARGET=target-files-package build/build.sh`. Analysis needs about 8 GB of RAM plus up to ~9 GiB of compressed zram pool (default cap 10G); see "Build host memory" below.
     - Launch it detached (`setsid nohup build/build.sh > log 2>&1 < /dev/null &`) when the caller may be killed: `docker run` forwards a signal to its parent into the build container, so a build can die with its shell.
     - `MFLAGS=-k` keeps going after the first error, so one run lists every compile error.
     - With other containers running, `MEM=7680m JOBS=3` stays under the VM guard; the default 8 GiB tripped it on 2026-11-16.
   - If `build/make/tools/releasetools` changed (a patch to `sign_target_files_apks.py`, for example), run `TARGET=otatools build/build.sh` first. `target-files-package` doesn't rebuild the host signing tools, so `sign.sh` would silently use the old ones: on 2026-11-16 that left `GmsCompatLib.apk` signed with the in-tree dev key.
   - `build/sign.sh`. It fails the release unless every `otacerts.zip` holds only our release certificate.
   - Check that no APK kept a dev key: `grep 'signing:' <sign log> | grep -v /lin/keys` must list nothing (`NOT signing:` lines are prebuilts that keep their own signatures).
   - Test-keys output is for development only.
6. **Make the packages:**
   - The full OTA comes from `sign.sh`.
   - Incrementals come from `publish.sh`, which calls `build/incremental.sh <source id> [target id]` for each recent older build. Keep every `*-signed-target_files.zip` on the build disk: an incremental needs the old one, and every build kept there gets a feed file.
7. **Test on the phone before publishing.**
   - Install over the previous release with the Updater's local import ([09-first-install.md](09-first-install.md#updating-an-installed-phone)): `adb push` the zip to `Download/`, then **Install local update**, **Install**, and reboot.
   - Check over adb: build date and slot, `sys.boot_completed`, no services stuck in `restarting`, crash buffer and `/data/tombstones`.
   - Hands-on: Wi-Fi, Bluetooth, cameras (including Night Vision, which exercises the camera HAL padding shim), fingerprint, GPS outdoors, IMS once a SIM is in. Later phases add GmsCompat Play services, the Play Integrity verdict, a banking app, the agent bridge, Titanium and Ovis.
   - If the build fails to boot, the logs are on the SD card through a debug OTA: `build/debug-sign.sh debug/sdlog` (see [09-first-install.md](09-first-install.md#logging-without-adb-debugsdlog)).
8. **Publish:** `build/publish.sh` (see below). Write the security patch levels of every layer into the release notes.

### Build host memory

- The build container is capped at 8 GB of RAM. Analysis puts ~26 GB of its heap in zram, at about 4:1 compression, and the zram pool also holds other workloads' cold pages (~3 GiB measured). An 8 GiB pool cap filled and the pressure watchdog killed two builds; 10G is now the default (`build/zram.sh`). The cap is write-only and can be raised live: `echo 10G > /sys/block/zram0/mem_limit` from a privileged container; `mm_stat` shows it.
- Don't run other heavy jobs during analysis (another project's CI, large adb pushes).
- Claude Code stops idle background shells when memory gets low, and `build.sh`'s watchdog lives in that shell. The `claude` alias sets `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`, so only the build's own guards end a build. If a build container is ever left running without its `build.sh`, stop it: it has no memory guard.

## OTA delivery from GitHub

What runs today, measured on build `1794688012` (2026-11-14):

```
build.sh -> sign.sh -> publish.sh ---> GitHub release cancunf-<build id>   (full OTA + incrementals)
                         |        \--> branch "ota": feed.json, <id>.json, ota.json  (the feed)
                  incremental.sh
phone: Updater -> raw.githubusercontent.com/.../ota/feed.json -> zip URL -> update_engine
```

Builds after `1794905814` all read the same `ota/feed.json`: the full OTA plus every incremental, each tagged with its source build. Updater patch 0001 drops incrementals made from another build, and drops the full OTA when an incremental to the same build applies, so each phone sees exactly what it can install. That works for builds that were never published too.

Earlier builds read older URIs, so their files stay: builds after `1794688012` through `1794905814` read `.../ota/{incr}.json`, where `{incr}` is the installed `ro.build.version.incremental` (our build id). Builds up to `1794688012` read the fixed `.../ota/ota.json`, which always holds the full OTA. A build with the `{incr}` URI that `publish.sh` never wrote a file for (a local build made after the last publish) gets HTTP 404, and the Updater shows "The update check failed"; that was the reason for `feed.json`.

**`build/publish.sh [build id]`** (defaults to the newest `/lin/release/<id>/`):

1. Finds every older build with signed target files in `/lin/release`. The newest `INCR_SOURCES` (default 3) get an incremental from `build/incremental.sh`, named `lineage-<version>-incr-<source id>-signed.zip`. It keeps an existing one after checking its metadata, and refuses a package whose metadata isn't A/B from that source to this target.
2. Reads the facts from the signed packages themselves (`build/feed.py` checks them): `ro.build.date.utc`, SDK level, security patch, `ro.lineage.releasetype` and version, each zip's size, SHA-256 and `ota-property-files`. It refuses a build that isn't `release-keys`.
3. Creates release `cancunf-<id>` with the full OTA and the incrementals, then checks GitHub's own SHA-256 of every uploaded asset against ours.
4. Force-pushes a one-commit `ota` branch with the feed files, and waits until `raw.githubusercontent.com` serves each one identically:
   - `feed.json`: the full OTA and every incremental, for builds after `1794905814`.
   - `<source id>.json` for every older build: its incremental, or the full OTA when it is older than the newest `INCR_SOURCES`. An incremental entry also carries `files[0].pre_build_incremental` (its source build), which our Updater patch uses for the label and to block it on any other build; stock LineageOS Updaters ignore the field.
   - `<id>.json` for the new build itself: `[]`, which the Updater shows as no update.
   - `ota.json`: the full OTA, for builds with the fixed URI.

   For the `{incr}` builds, one without a file gets HTTP 404, which the Updater shows as an error, so keep the target files of every such build that may be on a phone.
5. Deletes every older `cancunf-*` release and its tag. Only the latest release is kept on GitHub, and the old ones go only after the new feed is live, so the feed never points at a deleted file.

`DRY_RUN=1` makes the incrementals, prints the feed files and publishes nothing.

Measured on build `1794730100` (2026-11-15): each incremental takes about 2.5 minutes to make. From the previous build it was 220 KB (only the feed URI changed); from builds with the camera and secure-element patches missing it was about 6 MB. The phone installed the full OTA by streaming in 11.5 minutes, with nothing stored on `/data`. Uploading a 1.68 GB full OTA takes about 25 minutes on this connection (~1 MB/s).

Incremental install, measured on build `1794738550` over `1794730100` (2026-11-15, no source change between them): the feed `1794730100.json` offered the 215 KB incremental; `update_engine` logged `Detected a 'delta' payload` with `source_slot: A`, fetched one 206,101-byte range (`payload.bin`) through GitHub's redirect, verified the signature against `otacerts.zip` and every target partition by hash, ran postinstall, and reported `Update successfully applied` 52 seconds after tapping Install. That Updater labelled the entry "Full install: Safe to install over any previous build": stock LineageOS maps every installable entry to that string without looking at the package. Updater patch 0001 fixes that from build `1794744737` on. Verified on the phone (2026-11-15):

- **1794738550 -> 1794744737** (the patch itself, 3.26 MB incremental, still shown as "Full install" by the old Updater): delta from slot B, 57 s. The Updater's database migrated from version 4 to 5 on first start and kept its saved entry.
- **1794744737 -> 1794749579** (211 KB): the patched Updater shows "Incremental update: Installs only over the build running now"; delta from slot A, 58 s. After the reboot it ran on slot B; the snapshot merge finished in 3.4 s.
- **Wrong source:** importing the incremental from `1794738550` on `1794744737` with "Install local update" shows "Incremental update for a different build; it can't be installed over this one." and offers no Install button. The package's own metadata (`precondition.build_incremental`) supplied the source build.

**Updater on the phone: the LineageOS Updater**, with the feed set by device patch 0018 (`lineage.updater.uri`). Facts from its source that shaped the design:

- **The feed client doesn't follow redirects** (`followRedirects(false)`), so the feed can't be a release asset or `releases/latest/download/...`, which are both redirects. `raw.githubusercontent.com` answers 200 directly.
- **The zip download follows one redirect** on the same scheme (`setUseDuplicateLinks(true)`), which is exactly what a GitHub release asset needs (`github.com` → `release-assets.githubusercontent.com`).
- **Property values are capped at 91 bytes.** `https://raw.githubusercontent.com/coffeegrind123/cancunf-lineage24-hardened/ota/cancunf.json` was 92 and failed the build; `.../ota/{incr}.json` is exactly 91 and `.../ota/feed.json` is 89. A longer repository or branch name doesn't fit.
- **`{device}`, `{type}` and `{incr}` are replaced in the URI** (`UpdatesNetworkDataSource.kt`). A non-2xx answer is an error, not "no updates".
- An entry is offered only if its `type` matches `ro.lineage.releasetype` (`UNOFFICIAL`), its `datetime` is newer than the installed `ro.build.date.utc`, and its `os_sdk_level` is not lower. A published build can't be reinstalled by mistake.
- **Streaming:** each entry carries `ota_property_files` (the package's `ota-property-files` metadata). With it, and "stream updates" on (the default), the Updater reads `payload_properties.txt` with a range request and has `update_engine` fetch `payload.bin` straight from the release URL, so the zip is never stored on `/data`. Both follow GitHub's redirect: `SingleRangeHttpFetcher` uses OkHttp's default, and `update_engine` sets `CURLOPT_FOLLOWLOCATION` with up to 10 redirects. A range request through the redirect returns 206 (checked with curl, 2026-11-15). Turning streaming off in the Updater's preferences falls back to download, verify, install.
- Without the property, the Updater contacts `download.lineageos.org`. Builds with patch 0018 no longer do.

**Hosting limits.** GitHub release files must be under 2 GiB. The full OTA is 1.68 GB; growth from GmsCompat, Pixel assets and preloads (phases 2, 7, 10) could cross it, so check every release. The fastboot images zip (2.37 GB) is only needed for a first install and isn't published.

**Later: the GrapheneOS Updater**
([GrapheneOS/platform_packages_apps_Updater](https://github.com/GrapheneOS/platform_packages_apps_Updater), MIT, branch `17`). It updates unattended through `update_engine`, streams the payload and prefers incrementals. Open before porting: whether it depends on GrapheneOS's own `update_engine` changes, whether `update_engine` follows GitHub's redirect and gets range requests for streaming, and its metadata format (`script/generate-metadata`). Until that is verified, the LineageOS Updater above stays.
