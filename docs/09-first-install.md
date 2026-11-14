# First install and debugging a bootloop

The first install of the release-signed build (2026-11-12), what went wrong on the way, and how the bootloop it ended in was diagnosed without adb. Everything here was measured on the phone. Where something is still unexplained, it says so.

## Starting state

- Stock Android 14 `U1TDS34.94-12-7-6` on slot A, 12-7-5 on slot B. Bootloader unlocked, data backed up ([01-backup](01-backup.md)).
- The release OTA and the fastboot image zip from [`build/sign.sh`](../build/sign.sh).

## Install route that worked

PixelOS's documented flow for cancunf is: fastbootd, flash `boot` and `vendor_boot`, wipe in recovery, `adb sideload` the ROM. On this build the sideload step failed twice, for two different reasons (below), so the install that worked was:

1. `adb reboot fastboot` from stock Android reaches **Motorola's fastbootd** (`getvar is-userspace: yes`). Flash `boot` and `vendor_boot` there. The bootloader's own fastboot refuses with `Preflash validation failed`.
2. From the bootloader menu, choose **Recovery mode**. That boots our LineageOS recovery.
3. Copy the OTA zip to a FAT32 microSD card and insert it. **Factory reset → Format data**, then **Apply update → SD card**. Recovery offers the SD card option only when a card is mounted.
4. Answer **No** to "reboot to recovery to install additional packages", then reboot.

The install writes the inactive slot and switches to it, so each later install goes to the other slot. The firmware in the OTA comes from `V1TDS35H.83-20-5-11`; after the first install the bootloader reports `MBM-3.1-cancunf_g_vext-31a87-V1TDS35H.83-20-5-11`.

## Problems on the way

### Motorola's recovery came up instead of ours

After flashing our `vendor_boot` in Motorola's fastbootd, `fastboot reboot fastboot` and `fastboot reboot recovery` both still brought up **Motorola's** fastbootd and recovery (`version-os: 12`, the "Android Recovery" header). Choosing Recovery mode from the bootloader menu brought up ours. Sideloading into Motorola's recovery fails with `failed to verify whole-file signature` and `Install completed with status 2`: its `otacerts.zip` holds only Motorola's OTA certificate. Our OTA itself verifies. `check_ota_package_signature.py` passes, and recovery's log shows the same SHA-256 digest (`failed to verify against RSA key 0`, one key loaded).

Unexplained: why the fastboot reboot commands reached the old recovery. Use the bootloader menu.

### Our recovery doesn't show up on USB

In our recovery and its fastbootd, the phone never appears on USB: no device, no error and no PnP event on the PC, even after replugging. Recovery's log shows the gadget side ready (`sys.usb.ffs.ready=1`, minadbd opens `/dev/usb-ffs/adb/ep0`), then `Timeout waiting for messages from minadbd`.

What was ruled out, from the kernel source and the images:

- `init.recovery.mt6855.rc` is byte-identical to YAAP's and PixelOS's.
- The recovery module list matches stock except for MTK debug modules that DragonHeart doesn't build.
- In this kernel, `cable_mode` defaults to normal, the `cmode` sysfs file is commented out, and `kernel_init_done` is never read. So the user-build-only `cmode` write and the missing `kernel_init_done` write don't matter.

Recovery's dmesg shows `musb-hdrc` registered, the Type-C controller (`mt6375-tcpc`, `rt-pd-manager`) probing fine, and the USB role switch set once at boot to role 0 with `VBUS_OFF`. Nothing changes after that. Those logs may have been taken with no cable in, so the next step is a capture with the cable plugged into a PC.

Status: open. SD-card installs work around it.

### Recovery trusts LineageOS's official key

The recovery `otacerts.zip` produced by signing holds our release certificate **and** `vendor/lineage/build/target/product/security/lineage.x509.pem`. LineageOS's releasetools adds it through `extra_recovery_keys`. So recovery accepts any zip signed by official LineageOS, which bypasses our own signing. Status: to be removed in `build/sign.sh` before the next release.

## The bootloop

The installed system never finished booting. The LineageOS animation kept running, and every few minutes the phone rebooted fully. That repeated until the bootloader ran out of retries on the slot.

Watching the phone's USB IDs from the PC showed the rhythm: `0E8D:2008` (MTP) appears when userspace is up, drops for 4–5 s about every 85 s with no `0E8D:2000` preloader port in between, so the phone hadn't restarted. That pattern is system_server restarting, not the kernel.

### Why adb couldn't be turned on

Two debug builds set `ro.adb.secure=0` and `persist.sys.usb.config=mtp,adb`. Neither enumerated adb:

- With `ro.debuggable=0` (this build's value), init's `update_sys_usb_config()` strips `adb` from `persist.sys.usb.config`.
- More fundamentally, `init.mt6855.usb.rc` sets `sys.usb.configfs 2`, which hands the gadget to the USB gadget HAL, driven by system_server's `UsbDeviceManager`. While system_server crash-loops, it resets the gadget to MTP at every restart, and adb never comes up, whatever the properties say.

pstore can't help either: the kernel has `CONFIG_PSTORE_RAM=y`, but neither the dtb nor dtbo defines a ramoops region, so no kernel log survives a reboot.

### Logging without adb: `debug/sdlog`

[`build/debug-sign.sh`](../build/debug-sign.sh) makes a signed debug OTA: the current build plus an overlay of extra files, signed the same way as `sign.sh`, so AVB and verity cover the additions. The [`debug/sdlog`](../debug/sdlog) overlay adds:

- **Android** (`/product/etc/init/dbglog.rc`, `/product/etc/dbglog.sh`): at `post-fs-data`, a service in the userdebug-only permissive `su` domain streams `logcat -b all` (rotating, 8 MB), plus dmesg, props, the process list, tombstones and ANR traces every 15 s, to `/metadata/dbglog/bootN/`. `/metadata` is unencrypted ext4, mounted in first stage, and vold doesn't touch it.
- **Recovery** (vendor_boot recovery fragment, `dbgcopy.rc` and `dbgcopy.sh`): on recovery start, it finds the SD card through sysfs (`11240000.mmc` → `mmcblk0p1` on this phone), then every 20 s for 5 minutes copies `/metadata/dbglog` plus recovery's own dmesg, props, `recovery.log` and USB state to `<card>/dbglog-recN/`.

Usage: install the debug OTA from the card, let the phone loop for a few minutes, go to recovery from the bootloader menu, wait 5 minutes, then read the card on a PC.

An earlier variant that wrote to the SD card directly from Android produced nothing. The likely reason is vold mounting and fsck'ing the card at the same time, but that wasn't confirmed.

### Root cause

From the captured logcat, every system_server dies the same way:

```
W Watchdog: *** WATCHDOG KILLING SYSTEM PROCESS: Blocked in handler on main thread (main) for 66s
W Watchdog:     at com.android.server.HardwarePropertiesManagerService.nativeInit(Native Method)
```

`nativeInit` waits for the thermal HAL (`Waited one second for android.hardware.thermal.IThermal/default`, 633 times), and the HAL never starts:

```
F linker: CANNOT LINK EXECUTABLE "/vendor/bin/hw/android.hardware.thermal-service.mediatek":
          library "pixelatoms-cpp.so" not found
```

The HAL is built from `hardware/mediatek/aidl/thermal` and links `pixelatoms-cpp`. That library is defined in `hardware/google/pixel/pixelstats`, which is its **own** Soong namespace, and `device.mk` doesn't list it in `PRODUCT_SOONG_NAMESPACES`. Soong still links the HAL, but the library is never installed to `/vendor`. That's the same failure class as device patch 0008 (`power-libperfmgr`).

This was the only `CANNOT LINK` in two full boots. The other `dlopen` misses in the log are optional plugins: per-sensor camera tuning libraries, `android.hardware.audio.sounddose-vendor-impl.so`, Qualcomm's `libcdsprpc.so` and MTK tool libraries. They are left for the hardware matrix in phase 1.

Fix: export `hardware/google/pixel/pixelstats` (device patch 0015), rebuild, and check that `/vendor/lib64/pixelatoms-cpp.so` is in the image before installing.

**Confirmed 2026-11-14:** with patch 0015, `/vendor/lib64/pixelatoms-cpp.so` is in the image, an image-wide scan of `NEEDED` entries finds no other missing library, and release build `1794655118` boots to the setup wizard and into the OS.

## First boot: hardware check over adb (no SIM)

Release build `1794655118`, read-only checks with `dumpsys`/`getprop` a few minutes after setup (2026-11-14):

| Area | Result |
|---|---|
| Boot health | `sys.boot_completed=1`; crash buffer empty; no `CANNOT LINK` anywhere in the log |
| Thermal HAL | `ThermalHAL AIDL 3 connected: yes`, reporting real temperatures |
| Sensors | 39 hardware sensors, all running, including Moto's (CapSense, Stowed, ChopChop, dt-gesture) |
| Cameras | 3 devices (2 back, 1 front) |
| Wi-Fi | enabled, `wlan0` up |
| Bluetooth | controller up at boot (real address read), 0 crashes; then switched off from quick settings |
| Fingerprint | HAL present (`FingerprintProvider/defaultHIDL`), nothing enrolled |
| GNSS | MediaTek `mnld` running (`MTK_MNLD_default`) |
| Audio | audioserver running, four mixer output streams |
| NFC | on |
| Vibrator | present |
| Battery and charging | charging over USB, health good |
| Modem | baseband loaded on both slots, `ccci_mdinit` running, `OUT_OF_SERVICE` (no SIM) |
| IMS | `com.mediatek.ims` plus the `mtkIms` and `telephony_ims` services present; registration needs a SIM |

Found, not yet fixed:

- `mtk_secure_element_hal_service` restarts every 5 s: `android.hardware.secure_element@1.2::ISecureElement/SIM1` is missing from the device VINTF manifest, so registration is refused. That affects only UICC secure elements (SIM-based payments, some eSIM functions). Fix: declare the `SIM1`/`SIM2` instances.
- SELinux denials, none of which stops a service: Moto's vendor init scripts (block devices, sysfs, vendor props), `system_suspend` reading battery sysfs, and `vendor_init` setting MTK props.
- Optional `dlopen` misses from the bootloop logs (camera tuning libraries, `sounddose`) still need checking with real use: take photos, play audio.

Not checkable without interaction: photo and video capture, playback and calls, fingerprint enrolment, a GPS fix, Wi-Fi and Bluetooth connections, and SIM features.
