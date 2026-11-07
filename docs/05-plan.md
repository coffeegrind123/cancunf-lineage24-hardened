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
| frameworks/base | *pending* | *pending* |
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
- **Graphene's kernel patches.** They target Pixel kernels; this phone runs Motorola's prebuilt GKI 5.10.
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
