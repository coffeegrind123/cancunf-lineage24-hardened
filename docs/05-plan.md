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

## Phases

0. **Build host:** done. See [04-build-host.md](04-build-host.md).
1. **Plain LineageOS 24 cancunf:**
   - product makefile, build, flash
   - check the hardware matrix and IMS service startup
   - restore path: [01-backup.md](01-backup.md)
2. **GmsCompat port** plus sandboxed Play.
3. **Hardening**, one feature per build, each verified on the phone.
4. **Integrity support** in the framework.
5. **Calls and SMS end to end** once a SIM is available.
6. **On-device coding agent with system access.** Details in the section below.
7. **Preloaded apps:** Titanium Browser and Ovis. Details in the section below.
8. **OTA updates from GitHub**, with the GrapheneOS Updater (LineageOS Updater as fallback) and a periodic re-port and release procedure. See [07-maintenance.md](07-maintenance.md).
9. **Our own kernel**: a DragonHeart fork kept current with Google `android12-5.10` and GrapheneOS kernel hardening. See [08-kernel.md](08-kernel.md).

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

## Preloaded apps

**[Titanium Browser](https://github.com/jqssun/android-titanium-browser)**
- About 3.1k stars, GPL-2.0, releases every few days. Chromium, based on GrapheneOS Vanadium, with extension support.
- Shipped as a prebuilt arm64 APK (about 335 MB) with the author's signature kept (`PRESIGNED`), so its own updates from GitHub or Play keep installing over it.
- It replaces the browser only. The system WebView is handled separately in phase 3.

**[Ovis](https://github.com/devswha/ovis)**
- About 1.9k stars, MIT. A chat and terminal client for [herdr](https://github.com/herdrdev/herdr), a Rust runtime that hosts coding agents, including pi, in panes.
- Designed for a PC-side server with the phone as a remote client.
- The Android app (`sh.ovis.app`, Capacitor, in `app/android`) is only a Play Store beta with no APK release, so we **build it from source** into the ROM. Signed with our key, it is updated with the ROM rather than from Play.

Running Ovis against an agent **on the phone** has two unsupported pieces:
- herdr's installer deliberately rejects Android. Its Linux arm64 binary was reported working in F-Droid Termux at v0.8.2 ([herdr #3857](https://github.com/herdrdev/herdr/issues/3857)), but not officially.
- The Ovis server is Bun, which has no native Android/bionic build.

The planned route is herdr plus the Ovis server inside a proot Debian in Termux, with the Ovis app connecting to `localhost:7317`. The same app also reaches pi on a PC. Both are unverified on Android 17 until tested on the phone.
