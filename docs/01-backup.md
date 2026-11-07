# Stock backup and restore

This is the procedure used on a factory-reset XT2343-2 running stock `U1TDS34.94-12-7-6` (Android 14, RETEU channel). The bootloader was unlocked and root was temporary, then removed.

## What the phone looks like

- **Storage:** UFS, three LUNs.
  - `sda` and `sdb` are the preloader LUNs (`preloader_a` and `preloader_b`), 4 MiB each.
  - `sdc` is the main LUN: 76 partitions, 128 GB.
- **A/B slots.** Before any flashing, slot A ran `12-7-6` (vbmeta rollback index 12). Slot B held the previous OTA, `12-7-5` (rollback index 10), and had never been booted since.
- **`by-name` aliases:** `bootloader1`/`bootloader2` are dangling, and `preloader_{emmc,ufs,raw}_*` are aliases of `sda`/`sdb`. These are skipped so each device is dumped once.
- **Mounted read-write while Android runs:** `metadata`, `nvcfg`, `nvdata`, `persist`, `prodpersist`, `protect1` and `protect2`.

## Partitions you cannot download again

Motorola's firmware packages don't contain:
- `nvram`, `nvdata`, `nvcfg`: radio calibration and IMEI
- `persist`, `prodpersist`, `protect1/2`
- `proinfo`, `utags`, `hw`, `carrier`, `cid`, `frp`, `seccfg`, `efuse`, `otp`

Losing them means losing cellular service permanently. They are the reason to take a dump at all.

The official RETEU `flashfile.xml` **erases `nvdata`** (along with userdata and metadata), and it only flashes slot `_a`. So a Motorola rescue flash is not harmless to per-device data.

## Taking the dump

You need root (see [03-root.md](03-root.md)). Then:

```sh
adb push scripts/backup/device-dump.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/device-dump.sh'          # stages ~7.5 GB in /data/local/tmp/bk
adb pull /data/local/tmp/bk/. ./dump/images                  # adb pull, NOT exec-out (below)
adb shell su -c 'rm -rf /data/local/tmp/bk'
```

What the script does:
- Each partition is copied with `dd` to `/data/local/tmp/bk/<name>.img` and hashed **on the phone**, into `SHA256SUMS`.
- Partitions mounted read-write are frozen for the duration of their copy (`busybox fsfreeze --freeze`; Magisk's busybox wants the long options). A trap thaws them on any exit.
- Afterwards it runs `e2fsck -fn` on the seven ext4 images.
- It also captures the primary and backup GPT of `sdc` (1 MiB each, head and tail).

Two traps found along the way:
- **The phone's `sh` does 32-bit arithmetic.** `$(( bytes / 4096 ))` on a 128 GB LUN goes negative. Use the sector count from `blockdev --getsz` instead.
- **`adb exec-out "su -c 'cat …'"` is not binary-safe.** It added 9 bytes to an 8 MiB file. `adb pull` matched the on-phone hash.

## Verifying it

- **Transfer:** re-hash every file on the host against the on-phone `SHA256SUMS`. All 79 matched (77 partitions plus the 2 GPT captures).
- **Factory state of slot images:** for each slot, recompute every hash descriptor in that slot's **signed** `vbmeta_<slot>` against the dumped images, using `sha256(salt + image[:image_size])`.
  - Slot A: `dtbo` and `vendor_boot` match. `boot` doesn't, because it carried Magisk when dumped.
  - Slot B: `boot`, `dtbo` and `vendor_boot` all match.
- **Factory `boot_a`:** the boot digest in the phone's signed `vbmeta_a` is `dc4fab17106f37f7204f9f782e26b8ed82043aa23cf17731dc1f8273a4d96d8a`.
  - The RETBR `12-7-6` `boot.img` hashes to exactly that.
  - Its kernel (`5.10.205-android12-9-00029-g3f12df86bfdb-ab11799032`, built Apr 19 2024) and its ramdisk build properties also match what the running phone reported.
  - So it is the factory `boot_a`, and it goes in `stock/boot_a.img`.

## Restoring

**Firmware set** (bootloader mode, unlocked):

```powershell
scripts\restore\restore-fastboot.ps1 -BackupDir D:\g54-backup                      # dry run: verify hashes, identity, lock state
scripts\restore\restore-fastboot.ps1 -BackupDir D:\g54-backup -Go -Wipe            # both slots + super, then factory reset
scripts\restore\restore-fastboot.ps1 -BackupDir D:\g54-backup -Go -Only boot_a     # one partition
```

- The script flashes lk, tee, vbmeta, md1img, boot, vendor_boot, dtbo and the rest for both slots, in Motorola's flash order, with `super` last.
- `boot_a` comes from `stock/`, not from the rooted dump.
- `-Only boot_a -Go` was used for real: the phone booted stock again.

**Per-device partitions** (rooted Android only; Motorola's bootloader won't take them):

```sh
adb push dump/images/nvdata.img dump/images/SHA256SUMS scripts/restore/device-restore.sh /data/local/tmp/rs/
adb shell su -c 'sh /data/local/tmp/rs/device-restore.sh nvdata'          # dry run
adb shell su -c 'GO=1 sh /data/local/tmp/rs/device-restore.sh nvdata'
```

What it checks and how it writes:
- Before writing: hash against the manifest, image size against partition size, and that the device is a `cancunf`.
- It refuses `userdata`, `seccfg` and `efuse`.
- Each write is verified by reading it back.
- Mounted partitions are frozen first, and the script ends with a no-sync `reboot -f`. A clean unmount would flush the kernel's old view of the filesystem over the restored image.

## Anti-rollback

- Slot A's vbmeta rollback index is 12.
- The RETEU `12-9-10-2` package lists bootloader anti-rollback 1 for every component, in its `signing-info.txt`.
- Flashing firmware with higher values (likely Android 15 builds) can permanently stop older bootloader images, including those in a `12-7-6` dump, from booting.
- Read `signing-info.txt` before flashing any package.
