# cancunf-lineage24-hardened

A LineageOS 24 (Android 17) build for the **moto g54 5G** (XT2343-2, `cancunf`, MediaTek Dimensity 7020 / MT6855), hardened with what GrapheneOS's work allows on this hardware. It also covers the full stock backup taken before any of it.

| Area | Status |
|---|---|
| Full stock backup, both slots, all partitions except userdata | done, hash-verified, factory `boot_a` proven against signed vbmeta |
| Restore tooling (fastboot set + root-only per-device partitions) | done; `boot_a` restore used for real |
| Bootloader unlock + temporary root (Magisk v27.0) | done; v28+ is refused by this bootloader, see [docs/03-root.md](docs/03-root.md) |
| Build host on Windows/WSL2 with a hard memory cap | prepared; LineageOS 24 source syncing |
| Plain LineageOS 24 for cancunf | planned (phase 1) |
| GrapheneOS GmsCompat (sandboxed Google Play) | planned (phase 2) |
| GrapheneOS hardening, as far as hardware allows | planned (phase 3) |
| Root-free Play Integrity support | planned (phase 4) |
| VoLTE calls / SMS | phase 5. No SIM yet, so only the no-SIM half can be verified |

## Docs

1. [Stock backup and restore](docs/01-backup.md): what was dumped, how it was verified, and how to put it back.
2. [Windows fastboot with a Motorola bootloader](docs/02-windows-fastboot.md): the Zadig driver plus the interface GUID that `fastboot.exe` needs.
3. [Unlock and root](docs/03-root.md): the unlock, why v28+ Magisk images fail with `Preflash validation failed`, and the v27.0 route.
4. [Build host](docs/04-build-host.md): an ext4 VHDX on a spare drive, a Docker volume on the raw device, and a cgroup-capped build container.
5. [Plan](docs/05-plan.md): why a device build rather than a GSI, the GrapheneOS port survey, and the banking limits.

## Layout

```
scripts/backup/device-dump.sh        on-phone (root): image every partition, freeze rw filesystems, hash
scripts/restore/restore-fastboot.ps1 Windows: verified fastboot restore of the firmware set, both slots
scripts/restore/device-restore.sh    on-phone (root): restore nvdata/persist/... with readback verification
scripts/windows/*.ps1                fastboot GUID fix, build-disk creation and re-attach
build/                               Dockerfile, local manifest, sync, survey and capped build scripts
```

Nothing device-unique is in this repository: no images, serials, IMEIs or unlock data. Your own dump is yours to keep private, because it contains your IMEI, calibration data and device keys.

## Related work

- [groxaxo/moto-g54-android17-lineageos24](https://github.com/groxaxo/moto-g54-android17-lineageos24): a LineageOS 24 GSI on cancunf via DSU. It registered IMS but calls were never tested. This repo takes the device-tree route instead ([why](docs/05-plan.md#why-not-a-gsi)).
- Device trees: [yaap/device_motorola_cancunf](https://github.com/yaap/device_motorola_cancunf) and [PixelOS-Devices/android_device_motorola_cancunf](https://github.com/PixelOS-Devices/android_device_motorola_cancunf), `seventeen` branches.
- [GrapheneOS](https://grapheneos.org): the source of GmsCompat and the hardening.
