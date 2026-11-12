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
   - `build/zram.sh on`
   - `build/build.sh` (the default target, `bacon`)
   - `TARGET=target-files-package build/build.sh`
   - `build/sign.sh`
   - Test-keys output is for development only.
6. **Make the packages:**
   - a full OTA
   - incrementals from the previous published releases. Keep every published `target_files.zip` on the build disk, because an incremental needs the old one.
7. **Test on the phone before publishing.**
   - Install the update over the previous release.
   - Check: boot, slot switch, IMS service up, Wi-Fi, Bluetooth, cameras, fingerprint, GmsCompat Play services, Play Integrity verdict, banking app.
   - Check that the agent bridge, Titanium and Ovis still work.
8. **Publish.** Create a GitHub release with the OTA packages, the update metadata and release notes, and record the security patch levels of all layers.

## OTA delivery from GitHub

**Hosting.** Updates are GitHub release assets on this repo.
- GitHub limits each release file to under 2 GiB. PixelOS's comparable full zip is 2.81 GB (`PixelOS_cancunf-16.2-20260609-0618.zip`), which raised the question of whether ours would fit.
- **Measured on our first release: the signed full OTA is 1.68 GB** (1,680,937,359 bytes), under the limit. It fits as a GitHub release asset as it stands. Growth from GmsCompat, Pixel assets and preloads (phases 2, 7, 10) could push it over; check each release, and move full packages to other hosting only if one crosses 2 GiB.
- The fastboot images zip is 2.37 GB, over the limit. It is only needed for a first install and is not published.

**Updater on the phone: the GrapheneOS Updater**
([GrapheneOS/platform_packages_apps_Updater](https://github.com/GrapheneOS/platform_packages_apps_Updater), MIT, branch `17`)

- **What it is.**
  - It updates automatically in the background through `update_engine`, streams the payload, prefers incremental packages, and falls back to a full package.
  - Release channels (stable/beta) can be chosen in its settings.
  - The server URL is one resource (`res/values/config.xml` → `url`), overridden with an overlay rather than a fork.
  - It reads `<url><device>-<channel>` metadata, then downloads update files from the same base.
  - The metadata format comes from GrapheneOS's [`script/generate-metadata`](https://github.com/GrapheneOS/script).
- **Base URL:** `https://github.com/coffeegrind123/cancunf-lineage24-hardened/releases/latest/download/`.
  - GitHub redirects that to the latest release's files, so `cancunf-stable` and the update packages resolve there.
  - Each release has to carry the incrementals from earlier builds as well as the full OTA.
- **Open questions, to test first:**
  - Whether `update_engine`'s HTTP fetcher follows GitHub's redirect to the storage host and gets the range requests that streaming needs.
  - Whether the Updater depends on GrapheneOS's `system/update_engine` changes (GrapheneOS ships its own `platform_system_update_engine`).

**Fallback: LineageOS Updater**, already in the build.
- Point the `lineage.updater.uri` property at a JSON file. LineageOS's v2 format:
  - per build: `datetime`, `type`, `version` and `files[]`
  - per file: `filename`, `size`, `url`, `os_patch_level`, `sha256`
- It downloads and then installs. The JSON can be a release asset, for example `releases/latest/download/updates.json`.
- It is manual (the user taps install), but needs no porting.

The GrapheneOS Updater is the target, because it gives the same unattended experience as GrapheneOS. The LineageOS Updater stays available until the GrapheneOS one is verified on the phone.
