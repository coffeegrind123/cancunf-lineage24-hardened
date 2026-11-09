# References

Every external source used so far, grouped by topic.

## Prior work on this phone

- [groxaxo/moto-g54-android17-lineageos24](https://github.com/groxaxo/moto-g54-android17-lineageos24): LineageOS 24 GSI on cancunf via DSU. Its notes: [CELLULAR.md](https://github.com/groxaxo/moto-g54-android17-lineageos24/blob/main/docs/CELLULAR.md), [PORTING_NOTES.md](https://github.com/groxaxo/moto-g54-android17-lineageos24/blob/main/docs/PORTING_NOTES.md), [INSTALLATION.md](https://github.com/groxaxo/moto-g54-android17-lineageos24/blob/main/docs/INSTALLATION.md).
- [eyzner/LineageOS-GSI releases](https://github.com/eyzner/LineageOS-GSI/releases): LineageOS 24 GSI binaries (Vanilla, GApps, microG). [2026-11-04 release](https://github.com/eyzner/LineageOS-GSI/releases/tag/lineage-24.0-20261104).
- [TrebleDroid ImsSettings.kt](https://github.com/TrebleDroid/treble_app/blob/master/app/src/main/java/me/phh/treble/app/ImsSettings.kt): the IMS APK selection the GSI port relied on.
- [AOSP Dynamic System Updates](https://source.android.com/docs/core/ota/dynamic-system-updates).
- [cyberknight777/dragonheart_kernel_motorola_cancunf](https://github.com/cyberknight777/dragonheart_kernel_motorola_cancunf) and [cancunf_releases](https://github.com/cyberknight777/cancunf_releases/blob/master/changelog_r.md): the custom kernel the GSI port ran on.

## Device trees (Android 17, `seventeen`)

- YAAP:
  - [device_motorola_cancunf](https://github.com/yaap/device_motorola_cancunf/tree/seventeen)
  - [device_motorola_cancunf-kernel](https://github.com/yaap/device_motorola_cancunf-kernel/tree/seventeen)
  - [vendor_motorola_cancunf](https://github.com/yaap/vendor_motorola_cancunf/tree/seventeen)
  - [vendor_motorola_cancunf-motcamera](https://github.com/yaap/vendor_motorola_cancunf-motcamera/tree/seventeen)
  - [hardware_mediatek](https://github.com/yaap/hardware_mediatek/tree/seventeen)
  - [device_mediatek_sepolicy_vndr](https://github.com/yaap/device_mediatek_sepolicy_vndr/tree/seventeen)
  - [packages_apps_DisplayFeatures](https://github.com/yaap/packages_apps_DisplayFeatures/tree/seventeen)
- PixelOS: [android_device_motorola_cancunf](https://github.com/PixelOS-Devices/android_device_motorola_cancunf/tree/seventeen) and [custom.dependencies](https://github.com/PixelOS-Devices/android_device_motorola_cancunf/blob/seventeen/custom.dependencies).
- Earlier Android versions: [sarthakroy2002/device_motorola_cancunf](https://github.com/sarthakroy2002/device_motorola_cancunf) (fourteen to sixteen-qpr2).
- [twrpdtgen/android_device_motorola_cancunf](https://github.com/twrpdtgen/android_device_motorola_cancunf/blob/cancunf_g_vext-user-12-U1TDS34.94-12-7-6-42110d-release-keys/omni_cancunf.mk): generated from a `12-7-6` dump. It confirmed the vendor fingerprint of the stock build.

## LineageOS and AOSP

- [LineageOS/android, `lineage-24.0`](https://github.com/LineageOS/android/tree/lineage-24.0): the manifest, on top of `android-17.0.0_r1`.
- [Soong `config.go`, `HighmemParallel()`](https://github.com/LineageOS/android_build_soong/blob/lineage-24.0/ui/build/config.go): `NINJA_HIGHMEM_NUM_JOBS` and the RAM-based pool sizing.
- [LineageOS hardware_mediatek](https://github.com/LineageOS/android_hardware_mediatek) and [device_mediatek_sepolicy_vndr](https://github.com/LineageOS/android_device_mediatek_sepolicy_vndr), `lineage-24.0`.
- [repo launcher](https://storage.googleapis.com/git-repo-downloads/repo).
- [avbtool.py](https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py).
- [AOSP platform-signed shared UID allowlist](https://source.android.com/docs/core/permissions/platform-signed-shared-uid-allowlist).
- [Android Platform-Tools for Windows](https://dl.google.com/android/repository/platform-tools-latest-windows.zip).
- Checked for an Android 17 GSI base, and found none:
  - [TrebleDroid/device_phh_treble](https://github.com/TrebleDroid/device_phh_treble): newest branch `android-16.0`.
  - [AndyCGYan/lineage_build_unified](https://github.com/AndyCGYan/lineage_build_unified): newest branch `lineage-22-light`.

## GrapheneOS

- [grapheneos.org](https://grapheneos.org).
- [platform_manifest, `17`](https://github.com/GrapheneOS/platform_manifest/blob/17/default.xml): based on `android-17.0.0_r1`.
- [platform_frameworks_base, `17`](https://github.com/GrapheneOS/platform_frameworks_base/tree/17): GmsCompat lives under `core/java/com/android/internal/gmscompat/`.
- [platform_packages_apps_GmsCompat, `17`](https://github.com/GrapheneOS/platform_packages_apps_GmsCompat/tree/17).
- Other surveyed repos (branch `17`):
  - [libcore](https://github.com/GrapheneOS/platform_libcore/tree/17)
  - [art](https://github.com/GrapheneOS/platform_art/tree/17)
  - [bionic](https://github.com/GrapheneOS/platform_bionic/tree/17)
  - [build](https://github.com/GrapheneOS/platform_build/tree/17)
  - [Settings](https://github.com/GrapheneOS/platform_packages_apps_Settings/tree/17)
  - [opt_telephony](https://github.com/GrapheneOS/platform_frameworks_opt_telephony/tree/17)
  - [sepolicy](https://github.com/GrapheneOS/platform_system_sepolicy/tree/17)
  - [Permission](https://github.com/GrapheneOS/platform_packages_modules_Permission/tree/17)
  - [native](https://github.com/GrapheneOS/platform_frameworks_native/tree/17)

## Stock firmware

- [lolinet mirror, cancunf official](https://mirrors.lolinet.com/firmware/lenomola/2023/cancunf/official/): all channels. [RETEU](https://mirrors.lolinet.com/firmware/lenomola/2023/cancunf/official/RETEU/) has `U1TDS34.94-12-9-10-2`, the nearest Android 14 package to `12-7-6`.
- [romstockbr: XT2343-1 RETBR U1TDS34.94-12-7-6](https://www.romstockbr.com/2024/08/firmware-motorola-moto-g54-xt2343-1.html): the source of the `12-7-6` `boot.img` that was proven to be the factory `boot_a`.
- Other `12-7-6` indexes seen in search, not used:
  - [ideiabr](https://www.ideiabr.com/2026/05/motorola-moto-g54-xt2343-1-cancunf_3.html)
  - [ravigautamtools](https://ravigautamtools.com/index.php?a=downloads&b=folder&id=9591)
  - [halabtech XT2343-5](https://support.halabtech.com/index.php?a=downloads&b=folder&id=179349)
  - [clansoft](https://www.clansoft.net/dl/index.php?a=downloads&b=folder&id=3093)
  - [firmwaredrive](https://firmwaredrive.com/index.php?a=downloads&b=folder&id=19586)

## Unlock, root, and `Preflash validation failed`

- [Motorola bootloader unlock](https://en-us.support.motorola.com/app/standalone/bootloader/unlock-your-device-b).
- [Magisk releases](https://github.com/topjohnwu/Magisk/releases): [v27.0](https://github.com/topjohnwu/Magisk/releases/tag/v27.0) works here; v28 and later are refused.
- [Magisk #8389](https://github.com/topjohnwu/Magisk/issues/8389): Motorola devices refuse v28+ patched images, and v27.0 works.
- [Magisk #8373](https://github.com/topjohnwu/Magisk/issues/8373): the same on a moto g54 XT2343-6.
- [MagiskFansShare: Moto G54 Preflash Validation Failed](https://magisk-talk.jizhiku.net/archives/31/).
- MagiskFansShare: Moto G64 v28+ issue, [504](https://magisk-talk.jizhiku.net/archives/504/) and [503](https://magisk-talk.jizhiku.net/archives/503/).
- [DroidWin: Preflash Validation Failed](https://droidwin.com/preflash-validation-failed-fix/): a generic fastbootd tip.
- [XDA: Motorola Edge 2025 vbmeta trick for MTK preflash](https://xdaforums.com/t/guide-root-motorola-edge-2025-oulu-xt2519-1-with-magisk-the-vbmeta-trick-for-mtk-preflash.4800864/): HTTP 403 when fetched.
- [XDA: XT2513-1 moto g 2025 unlock and root](https://xdaforums.com/t/xt2513-1-motorola-g-2025-metropcs-bootloader-unlock-and-root.4730331/).
- [beyond-infra: Motorola MBM-3.0 rejects Magisk images](https://beyond-infra.github.io/posts/motorola-magisk-preflash-fix/): HTTP 404 when fetched.
- [bkerler/mtkclient](https://github.com/bkerler/mtkclient): MT6855 has a chip config but no BROM payload, so it can't do a pre-unlock dump.

## Windows USB

- [Zadig](https://zadig.akeo.ie) via [pbatard/libwdi v1.5.1](https://github.com/pbatard/libwdi/releases/tag/v1.5.1).

## On-device agents and preloads (phase 6)

- **pi:**
  - [earendil-works/pi](https://github.com/earendil-works/pi) (formerly `badlogic/pi-mono`)
  - [Termux guide](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/termux.md)
  - [MCP](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md)
- **Ovis and herdr:**
  - [ovis.sh](https://ovis.sh/)
  - [devswha/ovis](https://github.com/devswha/ovis)
  - [herdrdev/herdr](https://github.com/herdrdev/herdr)
  - [herdr #3857](https://github.com/herdrdev/herdr/issues/3857): Termux installation
- **Browser:**
  - [jqssun/android-titanium-browser](https://github.com/jqssun/android-titanium-browser)
  - [Titanium Extension](https://github.com/jqssun/android-titanium-extension)
  - [GrapheneOS Vanadium](https://github.com/GrapheneOS/Vanadium)
- **Computer Control and AppFunctions:**
  - [Android Computer Control (preview)](https://developer.android.com/ai/computer-control)
  - [AppFunctions](https://developer.android.com/ai/appfunctions)
  - [anotb/phone-use alternatives notes](https://github.com/anotb/phone-use)
- **Phone-control agents surveyed:**
  - [Operit](https://github.com/AAswordman/Operit)
  - [Mobilerun](https://github.com/droidrun/mobilerun)
  - [Mobilerun Portal](https://github.com/droidrun/mobilerun-portal)
  - [mobile-mcp](https://github.com/mobile-next/mobile-mcp)
  - [Android-MCP](https://github.com/CursorTouch/Android-MCP)
  - [Open-AutoGLM](https://github.com/zai-org/Open-AutoGLM)
  - [MobileAgent](https://github.com/X-PLUG/MobileAgent)
  - [UI-TARS](https://github.com/bytedance/UI-TARS)
  - [ClosePaw](https://github.com/imoonkey/closepaw)
  - [termux-mcp](https://github.com/termuxgpt/termux-mcp)
  - [mcpshell](https://github.com/xnet-admin-1/mcpshell)
- **Privilege layer:**
  - [Shizuku](https://github.com/RikkaApps/Shizuku)
  - [Termux](https://github.com/termux/termux-app)
  - [Termux:API](https://github.com/termux/termux-api)

## Updates and OTA (phase 8)

- [GrapheneOS Updater](https://github.com/GrapheneOS/platform_packages_apps_Updater): the automatic background updater. Server URL is in `res/values/config.xml`.
- [GrapheneOS script](https://github.com/GrapheneOS/script): `generate-metadata` for the Updater's server files.
- [GrapheneOS releases.grapheneos.org](https://github.com/GrapheneOS/releases.grapheneos.org): their update server.
- [LineageOS Updater](https://github.com/LineageOS/android_packages_apps_Updater): the JSON format (`NetworkUpdate.kt`) and the `lineage.updater.uri` property.

## Kernel (phase 9)

- [coffeegrind123/kernel_motorola_cancunf](https://github.com/coffeegrind123/kernel_motorola_cancunf): our fork.
- [cyberknight777/dragonheart_kernel_motorola_cancunf](https://github.com/cyberknight777/dragonheart_kernel_motorola_cancunf): the base, with MediaTek drivers and `build.config.cancunf`.
- [yaap/device_motorola_cancunf-kernel](https://github.com/yaap/device_motorola_cancunf-kernel/tree/seventeen): the current prebuilts.
- [AOSP kernel/common `android12-5.10`](https://android.googlesource.com/kernel/common/+log/refs/heads/android12-5.10): Google's 5.10 kernel branch.
- [kernel.org releases](https://www.kernel.org/category/releases.html): stable series and their end-of-life dates.
- [GrapheneOS/kernel_common-6.1](https://github.com/GrapheneOS/kernel_common-6.1): GrapheneOS's kernel hardening (93 commits on `android14-6.1-lts`).
- [LineageOS kernel.mk](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-24.0/build/tasks/kernel.mk): building the kernel in-tree.

## PixelOS (cancunf builds, spoofing, Pixel layer)

- [PixelOS-AOSP](https://github.com/PixelOS-AOSP): the ROM's source, `seventeen` on `android-17.0.0_r1`.
- [official_devices cancunf](https://github.com/PixelOS-AOSP/official_devices/tree/seventeen/API): device entry, updater JSON and [install guide](https://github.com/PixelOS-AOSP/official_devices/blob/seventeen/API/instructions/cancunf.md) (ARB warning for `V1TDS35H.83-20-5-14`, fastbootd vs preflash validation, bundled A15 firmware).
- [pixelos.net/download/cancunf](https://pixelos.net/download/cancunf): latest official build, Android 16 (16.2, 2026-06-09).
- [android_build_soong](https://github.com/PixelOS-AOSP/android_build_soong): LineageOS soong plus small tweaks.
- [android_frameworks_base](https://github.com/PixelOS-AOSP/android_frameworks_base/tree/seventeen): `PlayIntegritySpoofService` and `PixelPropsUtils` (phase 4 source).
- [android_vendor_custom pixel.mk](https://github.com/PixelOS-AOSP/android_vendor_custom/blob/seventeen/config/pixel.mk) and [the Pixel repos on GitLab](https://gitlab.com/PixelOS-AOSP) (phase 10).
