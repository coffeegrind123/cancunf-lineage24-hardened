# Plan

## Goal

LineageOS 24.0 (Android 17) built for `cancunf`, with:

1. working MediaTek IMS: VoLTE calls and SMS
2. GrapheneOS **GmsCompat**: Google Play as an ordinary sandboxed app with no special privileges
3. as much GrapheneOS hardening as this hardware and firmware allow
4. banking apps without root: Play Integrity support built into the framework

## Why not a GSI

- [groxaxo's port](https://github.com/groxaxo/moto-g54-android17-lineageos24) ran eyzner's LineageOS 24 GSI under DSU. To get there it needed:
  - restored VINTF requirements and a camera SELinux mapping
  - a Trustonic secure-storage relocation
  - a shared-UID allowlist and a patched third-party IMS APK
- IMS did register with voice and SMS capability, but **no call was ever placed**, and mobile data failed.
- Building our own Android 17 GSI would mean porting TrebleDroid to Android 17 first: its newest public branch is `android-16.0`. eyzner's LineageOS 24 GSI is binary-only.
- Meanwhile YAAP and PixelOS maintain **Android 17 (`seventeen`) device trees for cancunf**. They integrate MediaTek's own IMS app properly: `hardware/mediatek` frameworks, mediatek-ims permissions, and `ImsService` patches 0001–0008 including the TelephonyMetrics removal.
- A device build needs none of the GSI workarounds.

## Sources

| What | Where |
|---|---|
| LineageOS | `LineageOS/android` `lineage-24.0`, on top of AOSP `android-17.0.0_r1` |
| Device, kernel (prebuilt GKI 5.10), vendor, motcamera, `hardware/mediatek`, `sepolicy_vndr`, DisplayFeatures | `yaap/*@seventeen` ([manifest](../build/local_manifests/cancunf.xml)) |
| GmsCompat and hardening | `GrapheneOS/*@17`, also on top of `android-17.0.0_r1` |

The YAAP tree inherits `vendor/yaap/config/common_full_phone.mk`. Phase 1 replaces it with a `lineage_cancunf.mk` on `vendor/lineage/config/common_full_phone.mk`, and audits BoardConfig for YAAP-only variables.

## GrapheneOS port survey

Graphene's own commits on top of `android-17.0.0_r1` on branch `17`. The counts come from blob-less clones with the AOSP tag fetched alongside: [`build/graphene-survey.sh`](../build/graphene-survey.sh).

| Repo | Commits on top of AOSP | Marked `gmscompat:` |
|---|---|---|
| frameworks/base | 538 | 19 (21 mention GMS or Play in total; counted via the GitHub API down to AOSP base `94b4c163`) |
| packages/apps/Settings | 184 | 0 (but "per-app Play Integrity API settings", sandboxed Play links) |
| build | 61 | 4 (GmsCompat app, `gmscompat_lib` signing keys) |
| bionic | 56 | 2 (linker: open zips by fd path) |
| system/sepolicy | 31 | 0 |
| frameworks/opt/telephony | 24 | 3 (SMS OTP broadcasts to GmsCore) |
| packages/modules/Permission | 21 | 2 |
| art | 19 | 3 (DEX from fd, GmsCompatLibrary platform API access) |
| frameworks/native | 18 | 1 |
| libcore | 14 | 4 (Dynamite modules, IoBridge.open hook) |

Plus the app itself, `platform_packages_apps_GmsCompat@17`.

Because both projects share the same AOSP base, most of these should cherry-pick. Conflicts come where LineageOS has changed the same code. Each port is a commit series per repo with original authorship kept.

## Hardening: what ports and what doesn't

**Ports** (framework and userspace):
- GmsCompat
- hardened_malloc
- exec-based app spawning
- Network and Sensors permission toggles
- Storage and Contact Scopes
- PIN scrambling, auto-reboot, Wi-Fi and Bluetooth auto-off
- system-side SELinux hardening
- Vanadium WebView

**hardened_malloc caveat:** Graphene already ships a per-process opt-out (`libc_globals` flag, vendor-process override, extended to static binaries). It disables hardened_malloc for the vendor audio service and the modem platform even on Pixels. Expect MediaTek vendor processes to need the same; find them from tombstones on the phone.

**Doesn't port:**
- **Verified boot with our own keys.** Motorola offers no user-settable root of trust, so the bootloader stays unlocked. This is GrapheneOS's core property, so the result is materially weaker than GrapheneOS.
- **MTE.** The Cortex-A78/A55 cores lack it.
- **Secure-element features.** They depend on the Pixel Titan chip.
- **GrapheneOS's kernel patches as-is.** They target Pixel 6.1/6.18. Phase 9 backports what applies to our own 5.10 kernel.
- **Modem, TEE and firmware updates.** Only Motorola can provide those.

## Banking

- Play Integrity spoofing goes **into the framework**, so no root is needed:
  - build properties presented to the GMS integrity check
  - keystore attestation hooks
- **The "device" verdict now needs hardware-backed attestation from an unrevoked keybox.** The keyboxes in circulation are other vendors' leaked private keys. This project does not source or ship one. The mechanism accepts a user-supplied keybox.
- **Without one, expect "basic" integrity only.** Some banks accept that; many don't.
- Relocking the bootloader with a custom OS is not possible on this phone.
- **Source to port:** PixelOS `frameworks_base@seventeen` has `core/java/android/security/pif/PlayIntegritySpoofService.java` and `core/java/com/android/internal/util/custom/PixelPropsUtils.java`, from the commit "spoof: Add Play Integrity spoofing with appcompat overrides" (2026-11-08). It handles the DroidGuard keybox path, spoofs a Pixel 10 Pro XL for GMS, and is configured through `Settings.Secure`. It is on the same Android 17 base and Apache-2.0. It is brand new, so pick up its follow-up fixes when porting.
- **Why LineageOS and not PixelOS as the base:** PixelOS builds for cancunf and is maintained by the device trees' author, but LineageOS is the more conservative and trusted base for security. We port selected PixelOS pieces (this spoofing, the Pixel look below) instead.

## Phases

0. **Build host:** done. See [04-build-host.md](04-build-host.md).
1. **Plain LineageOS 24 cancunf:**
   - product makefile and build: **done 2026-11-12.** Fourteen device patches, three vendor and one DisplayFeatures patch were needed ([04-build-host.md](04-build-host.md#our-changes-to-synced-trees)).
   - release keys and a release-signed OTA: done ([07-maintenance.md](07-maintenance.md#release-keys))
   - flash: **done 2026-11-14** from SD card; the phone is on Android 15 firmware (`V1TDS35H.83-20-5-11`), which the owner approved ([09-first-install.md](09-first-install.md)).
   - hardware matrix and IMS service startup: **done without a SIM** ([09-first-install.md](09-first-install.md#first-boot-hardware-check-over-adb-no-sim)). Calls wait for phase 5.
   - restore path: [01-backup.md](01-backup.md)
2. **GmsCompat port** plus sandboxed Play:
   - port: **done 2026-11-16**, about 100 GrapheneOS commits in 22 projects ([06-gmscompat-port.md](06-gmscompat-port.md)). It runs on the phone: GmsCore starts through the compatibility layer with its config, and the Play Store opens to its sign-in screen.
   - sandboxed Play, Aurora Store, F-Droid and Titanium Browser installed by AppSetup ([10-appsetup.md](10-appsetup.md)).
   - verified on the phone (2026-11-16, no Google account): GmsCore's device check-in and FCM registration (FCM Toolbox gets a token, "Online"); GmsCore's main process isn't frozen by the cached-app freezer while cached apps are; Play-services location requests are rerouted to the OS location service.
   - still to verify: FCM delivery of a real message, Play Store sign-in and an install, and the Play Integrity verdict (expected to fail until phase 4).
   - **location: port GrapheneOS's network location next** (details in "Location" below). Rerouting works, but indoors nothing answers: LineageOS ships no network location provider, and the GPS had no fix.
3. **Hardening**, one feature per build, each verified on the phone.
4. **Integrity support** in the framework.
5. **Calls and SMS end to end** once a SIM is available.
6. **On-device coding agent with system access.** Details in the section below.
7. **Apps outside the image:** Titanium Browser, Termux and Ovis through AppSetup. Details in the section below.
8. **OTA updates from GitHub**, with the GrapheneOS Updater (LineageOS Updater as fallback) and a periodic re-port and release procedure. Running now with the LineageOS Updater: a per-build feed, incrementals from the three newest older builds, streamed installs. See [07-maintenance.md](07-maintenance.md).
9. **Our own kernel**: a DragonHeart fork kept current with Google `android12-5.10` and GrapheneOS kernel hardening. See [08-kernel.md](08-kernel.md).
10. **Pixel look and feel**: Pixel fonts, sounds, clocks, ThemePicker and optionally Pixel Launcher, from PixelOS's Pixel vendor repos. Details in the section below.

## Phase 6: pi with free access to the system

No mature project combines an on-device coding agent with privileged control of the system. The pieces exist:

- **pi** ([earendil-works/pi](https://github.com/earendil-works/pi), MIT) officially supports Termux on Node 22. Custom tools plug in through MCP or `pi.registerTool` extensions, and extensions can intercept tool calls.
- **Phone-use agents** mostly drive the phone from a PC over adb (mobile-mcp, Mobilerun, AutoGLM, Mobile-Agent).
- **On-device MCP servers with system access** are all hobby projects with fewer than 50 stars.
- **Shizuku** has had no release since 2025-05.

Building the ROM ourselves lets us fill the gap properly:

1. **pi in Termux**, shipped with the ROM: Termux, Termux:API, Node 22.
2. **An agent bridge**: a priv-app signed with our platform key, running an MCP server on the phone that only the Termux uid (or a token holder) may connect to. It calls framework APIs directly:
   - Settings, including Secure and Global (`WRITE_SECURE_SETTINGS`)
   - installing and removing packages, granting permissions
   - force-stopping and starting apps
   - content providers
   - `INJECT_EVENTS` input and screenshots
   - its own AccessibilityService, enabled by default, for the UI tree
3. **A built-in Shizuku replacement**: an init service in its own SELinux domain that runs `cmd`, `pm`, `am` and `settings` at shell-uid level. This avoids depending on unmaintained Shizuku.
4. **Computer Control** (Android 17) for automating apps on a background virtual display.
   - `LineageOS/android_frameworks_base@lineage-24.0` has `libs/computercontrol/`.
   - It declares `ACCESS_COMPUTER_CONTROL` as `internal|privileged`, behind the flag `android.companion.virtualdevice.flags.computer_control_access`.
   - As the ROM builder we can grant it through `privapp-permissions` and give the bridge the assistant role.
   - **Open question:** whether its allowlists and the `com.android.extensions.computercontrol` extension work from LineageOS sources, or need Google components.
5. **Safety.** The bridge controls the whole phone, and anything the agent reads (pages, notifications, messages) can attempt prompt injection. So:
   - a pi extension asks for confirmation before installs, permission grants and risky settings changes
   - every bridge call is logged
   - optionally, the agent runs in its own Android user

## Phase 10: Pixel look and feel

PixelOS's Pixel features are a separate layer of Google binaries extracted from Pixel firmware, not part of its base. `vendor/custom/config/pixel.mk` in [PixelOS-AOSP/android_vendor_custom](https://github.com/PixelOS-AOSP/android_vendor_custom/blob/seventeen/config/pixel.mk) pulls them from public GitLab repos (`gitlab.com/PixelOS-AOSP/proprietary_vendor_pixel_*`, all with `seventeen` branches, checked 2026-11-09):

| Repo | What | Plan |
|---|---|---|
| `gsans`, `sounds`, `clocks` | Google Sans font, ringtones/notification sounds/wallpapers, lock-screen clocks | Add. Plain files and small APKs. |
| `themepicker` | Pixel wallpaper and style picker | Add. Uses the framework's theming, which LineageOS has. |
| `launcher` | Pixel Launcher | Optional, behind a build flag. As recents provider it needs framework config, and its search bar expects the Google app. Test it alongside GmsCompat. |
| `gms-17` | Google apps as privileged system apps | **Left out.** It contradicts GmsCompat's sandboxed Play. |

- These are Google's proprietary files. They are pulled into the tree at build time through the local manifest (with `android_vendor_pixel_extract-utils`), and never committed to this repo.
- Pixel-hardware features (Call Screen, Now Playing, Tensor camera processing) don't work on any non-Pixel phone.

## Location

GrapheneOS's sandboxed Play gets locations in three layers. The first is ported; the other two are next.

1. **GmsCompat reroutes Play-services location calls to the OS location service**, so Google's location service never sees them. Ported with phase 2 and working: a Maps request reaches the OS `gps` provider.
2. **Network location from GrapheneOS's own provider**, the NetworkLocation app ([platform_packages_apps_NetworkLocation](https://github.com/GrapheneOS/platform_packages_apps_NetworkLocation)). It does Wi-Fi positioning against Apple's Wi-Fi location database, queried through GrapheneOS's proxy (TLS 1.3 only). It's opt-in in Settings › Location and doesn't use cell towers. Without it a position needs a GPS fix, which indoors usually means none. To port:
   - the app (Rust with a JNI entry point, built by Soong) as a new manifest project;
   - frameworks/base: `df6a80b3bc` (add it to `config_locationProviderPackageNames`), `18c04e99d5` (network location setting), `3539c74dc5` (never remove location providers at runtime), and the fused-provider fixes `8cfd21e7e3`, `cc4fb8697c`, `ae077bd735`;
   - Settings: the network location toggle;
   - build: `d29beff2fd`, `7fedec9c19` (add NetworkLocation to the product).
3. **GNSS assistance through GrapheneOS's servers**: SUPL (`1259408b52`) and PSDS (`f47b691b97`) settings, plus `bd75ca83e6` (don't send the IMSI or phone number to the SUPL server), and their Settings pages (`d186cdd504`, `a2144665cd`). **Check on this phone first:** GrapheneOS wrote these for Pixel GNSS stacks; MediaTek's `mnld` reads SUPL from its own vendor configuration (`agps_profiles_conf2.xml`), so the settings may need a vendor-side counterpart to take effect.

Each piece goes through the same dependency closure and reference checks as the GmsCompat port ([06-gmscompat-port.md](06-gmscompat-port.md)). It's checked on the phone indoors (Wi-Fi fix within seconds) and outdoors (GPS fix, time to first fix).

## Apps outside the image

None of these are in the system image. [AppSetup](10-appsetup.md) installs them on first run and keeps them updated, each pinned to its signing certificate. That keeps the full OTA under GitHub's 2 GiB file limit: Titanium alone is 335 MB.

**[Titanium Browser](https://github.com/jqssun/android-titanium-browser)**
- About 3.1k stars, GPL-2.0, releases every few days. Chromium, based on GrapheneOS Vanadium, with extension support.
- AppSetup installs the arm64 GitHub release with its author's signature, and is its only updater.
- It replaces the browser only. The system WebView is handled separately in phase 3.

**Termux and Termux:API** (phase 6 needs them)
- From F-Droid, not GitHub. Termux's GitHub builds are signed with a test key whose private half is public in termux-app, so a pin on it would protect nothing, and any app signed with it could join Termux's shared `com.termux` UID. The phase 6 bridge plans to trust that UID.

**[Ovis](https://github.com/devswha/ovis)**
- About 1.9k stars, MIT. A chat and terminal client for [herdr](https://github.com/herdrdev/herdr), a Rust runtime that hosts coding agents, including pi, in panes.
- Designed for a PC-side server with the phone as a remote client.
- The Android app (`sh.ovis.app`, Capacitor, in `app/android`) is only a Play Store beta with no APK release, so we **build it from source**, sign it with our own key, publish it as a release asset of this repo, and add it to AppSetup pinned to that key.

Running Ovis against an agent **on the phone** has two unsupported pieces:
- herdr's installer deliberately rejects Android. Its Linux arm64 binary was reported working in F-Droid Termux at v0.8.2 ([herdr #3857](https://github.com/herdrdev/herdr/issues/3857)), but not officially.
- The Ovis server is Bun, which has no native Android/bionic build.

The planned route is herdr plus the Ovis server inside a proot Debian in Termux, with the Ovis app connecting to `localhost:7317`. AppSetup can start that setup in Termux through its `RUN_COMMAND` intent once Termux is installed.

**AppSetup follow-ups**
- Ovis: build from source, sign with our key, publish as a release asset of this repo, pin it in AppSetup.
- herdr and the Ovis server: a setup step that AppSetup starts in Termux (`RUN_COMMAND`, which needs Termux's `allow-external-apps`). It installs proot Debian, then herdr and the Ovis server, with checksums.
- Play links: optionally make Aurora Store the handler for Play links on a fresh install. On 2026-11-16 this was set by hand: `pm set-app-links-user-selection` for `play.google.com` and `market.android.com`, plus "Always" in the chooser for `market://`.
 The same app also reaches pi on a PC. Both are unverified on Android 17 until tested on the phone.
