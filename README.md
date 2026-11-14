# cancunf-lineage24-hardened

A LineageOS 24 (Android 17) build for the **moto g54 5G** (XT2343-2, `cancunf`, MediaTek Dimensity 7020 / MT6855), hardened with what GrapheneOS's work allows on this hardware. It also covers the full stock backup taken before any of it.

| Area | Status |
|---|---|
| Full stock backup, both slots, all partitions except userdata | done, hash-verified, factory `boot_a` proven against signed vbmeta |
| Restore tooling (fastboot set + root-only per-device partitions) | done; `boot_a` restore used for real |
| Bootloader unlock + temporary root (Magisk v27.0) | done; v28+ is refused by this bootloader, see [docs/03-root.md](docs/03-root.md) |
| Build host on Windows/WSL2 with a hard memory cap | done; Android 17 analysis runs with zram, see [docs/04-build-host.md](docs/04-build-host.md) |
| Plain LineageOS 24 for cancunf | boots: build `1794655118` (2026-11-14, release-signed) installed from SD card and through setup. The first build bootlooped on a missing thermal-HAL library, fixed by device patch 0015; see [docs/09-first-install.md](docs/09-first-install.md). Hardware matrix next. Port fixes in [docs/04-build-host.md](docs/04-build-host.md#our-changes-to-synced-trees) |
| Release keys and signing | done: [`build/keys.sh`](build/keys.sh), [`build/sign.sh`](build/sign.sh); keys stay on the build disk |
| GrapheneOS GmsCompat (sandboxed Google Play) | planned (phase 2) |
| GrapheneOS hardening, as far as hardware allows | planned (phase 3) |
| Root-free Play Integrity support | planned (phase 4) |
| VoLTE calls / SMS | phase 5. No SIM yet, so only the no-SIM half can be verified |
| pi coding agent with system access (privileged bridge, Computer Control) | planned (phase 6) |
| Preloaded Titanium Browser and Ovis | planned (phase 7) |
| OTA updates from GitHub releases (GrapheneOS Updater), periodic re-port | planned (phase 8), runbook in [docs/07-maintenance.md](docs/07-maintenance.md) |
| Pixel look and feel (fonts, sounds, clocks, ThemePicker, optional Pixel Launcher) from PixelOS's Pixel repos | planned (phase 10) |
| Own kernel ([fork](https://github.com/coffeegrind123/kernel_motorola_cancunf)): Google `android12-5.10` fixes plus GrapheneOS hardening | planned (phase 9), [docs/08-kernel.md](docs/08-kernel.md) |

## Docs

1. [Stock backup and restore](docs/01-backup.md): what was dumped, how it was verified, and how to put it back.
2. [Windows fastboot with a Motorola bootloader](docs/02-windows-fastboot.md): the Zadig driver plus the interface GUID that `fastboot.exe` needs.
3. [Unlock and root](docs/03-root.md): the unlock, why v28+ Magisk images fail with `Preflash validation failed`, and the v27.0 route.
4. [Build host](docs/04-build-host.md): an ext4 VHDX on a spare drive, a Docker volume on the raw device, and a cgroup-capped build container.
5. [Plan](docs/05-plan.md): why a device build rather than a GSI, the GrapheneOS port survey, and the banking limits.
6. [GmsCompat port](docs/06-gmscompat-port.md): commit order and prerequisites for porting GrapheneOS's sandboxed Google Play.
7. [Maintenance](docs/07-maintenance.md): which layers get security fixes and from where, release keys, the periodic update procedure, and OTA delivery from GitHub.
8. [Kernel](docs/08-kernel.md): our DragonHeart-based kernel, how GrapheneOS's 93 kernel hardening commits sort for 5.10, and the per-release kernel procedure.
9. [First install](docs/09-first-install.md): the install route that worked (SD card, not sideload), open recovery issues, and how the bootloop was diagnosed without adb.

## Layout

```
scripts/backup/device-dump.sh        on-phone (root): image every partition, freeze rw filesystems, hash
scripts/restore/restore-fastboot.ps1 Windows: verified fastboot restore of the firmware set, both slots
scripts/restore/device-restore.sh    on-phone (root): restore nvdata/persist/... with readback verification
scripts/windows/*.ps1                fastboot GUID fix, build-disk creation and re-attach
build/                               Dockerfile, local manifest, sync, survey and capped build scripts
build/zram.sh                        compressed RAM swap for the VM, which Android 17's analysis needs
build/keys.sh, build/sign.sh         release keys (on the build disk only) and release signing
build/soong-prune.py                 generates the device's Soong prune list
build/debug-sign.sh                  signed DEBUG OTA: the build plus an overlay of extra files
debug/sdlog/                         debug overlay: boot logs to /metadata, copied to the SD card by recovery
patches/<project>/                   our commits on top of the synced trees (build/apply-patches.sh)
```

Nothing device-unique is in this repository: no images, serials, IMEIs or unlock data. Your own dump is yours to keep private, because it contains your IMEI, calibration data and device keys.

## Related work

All sources used so far: [REFERENCES.md](REFERENCES.md).


- [groxaxo/moto-g54-android17-lineageos24](https://github.com/groxaxo/moto-g54-android17-lineageos24): a LineageOS 24 GSI on cancunf via DSU. It registered IMS but calls were never tested. This repo takes the device-tree route instead ([why](docs/05-plan.md#why-not-a-gsi)).
- Device trees: [yaap/device_motorola_cancunf](https://github.com/yaap/device_motorola_cancunf) and [PixelOS-Devices/android_device_motorola_cancunf](https://github.com/PixelOS-Devices/android_device_motorola_cancunf), `seventeen` branches.
- [GrapheneOS](https://grapheneos.org): the source of GmsCompat and the hardening.
