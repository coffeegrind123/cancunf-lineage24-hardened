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
5. **Build and sign.**
   - `build/zram.sh on` (after any VM restart; check with `build/zram.sh status`).
   - `TARGET=target-files-package build/build.sh`. Analysis needs about 8 GB of RAM plus up to ~9 GiB of compressed zram pool (default cap 10G); see "Build host memory" below.
   - `build/sign.sh`. It fails the release unless every `otacerts.zip` holds only our release certificate.
   - Test-keys output is for development only.
6. **Make the packages:**
   - The full OTA comes from `sign.sh`.
   - Incrementals from earlier published releases are still to do. Keep every published `*-signed-target_files.zip` on the build disk, because an incremental needs the old one.
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
build.sh -> sign.sh -> publish.sh ---> GitHub release cancunf-<build id>   (the OTA zip)
                                  \--> branch "ota": ota.json               (the feed)
phone: Updater -> raw.githubusercontent.com/.../ota/ota.json -> zip URL -> update_engine
```

**`build/publish.sh [build id]`** (defaults to the newest `/lin/release/<id>/`):

1. Reads the facts from the signed package itself: `ro.build.date.utc`, SDK level, security patch, `ro.lineage.releasetype` and version, the zip's size and SHA-256. It refuses a build that isn't `release-keys`.
2. Creates release `cancunf-<id>` with the OTA zip, then checks GitHub's own SHA-256 of the uploaded asset against ours.
3. Force-pushes a one-commit `ota` branch holding `ota.json`, and waits until `raw.githubusercontent.com` serves the identical file.
4. Deletes every older `cancunf-*` release and its tag. Only the latest release is kept on GitHub, and the old ones go only after the new feed is live, so the feed never points at a deleted file.

`DRY_RUN=1` prints the feed entry and publishes nothing. Uploading a 1.68 GB full OTA takes about 25 minutes on this connection (~1 MB/s).

**Updater on the phone: the LineageOS Updater**, with the feed set by device patch 0018 (`lineage.updater.uri`). Facts from its source that shaped the design:

- **The feed client doesn't follow redirects** (`followRedirects(false)`), so the feed can't be a release asset or `releases/latest/download/...`, which are both redirects. `raw.githubusercontent.com` answers 200 directly.
- **The zip download follows one redirect** on the same scheme (`setUseDuplicateLinks(true)`), which is exactly what a GitHub release asset needs (`github.com` → `release-assets.githubusercontent.com`).
- **Property values are capped at 91 bytes.** `https://raw.githubusercontent.com/coffeegrind123/cancunf-lineage24-hardened/ota/cancunf.json` was 92 and failed the build; `.../ota/ota.json` is 88.
- An entry is offered only if its `type` matches `ro.lineage.releasetype` (`UNOFFICIAL`), its `datetime` is newer than the installed `ro.build.date.utc`, and its `os_sdk_level` is not lower. A published build can't be reinstalled by mistake.
- `ota_property_files` (streaming offsets) is left out, so the Updater downloads, verifies, then installs.
- Without the property, the Updater contacts `download.lineageos.org`. Builds with patch 0018 no longer do.

**Hosting limits.** GitHub release files must be under 2 GiB. The full OTA is 1.68 GB; growth from GmsCompat, Pixel assets and preloads (phases 2, 7, 10) could cross it, so check every release. The fastboot images zip (2.37 GB) is only needed for a first install and isn't published.

**Later: the GrapheneOS Updater**
([GrapheneOS/platform_packages_apps_Updater](https://github.com/GrapheneOS/platform_packages_apps_Updater), MIT, branch `17`). It updates unattended through `update_engine`, streams the payload and prefers incrementals. Open before porting: whether it depends on GrapheneOS's own `update_engine` changes, whether `update_engine` follows GitHub's redirect and gets range requests for streaming, and its metadata format (`script/generate-metadata`). Until that is verified, the LineageOS Updater above stays.
