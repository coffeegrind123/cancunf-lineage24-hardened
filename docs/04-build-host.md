# Build host: Windows + WSL2 + Docker Desktop

The host is a Ryzen 9 3900X with 32 GB of RAM. The WSL VM is capped at 22 GB of memory and is shared with other workloads. The NVMe is nearly full; a 10 TB HDD has space. Android builds in that VM have twice exhausted memory and swap and taken Docker Desktop down. The setup below is built so that only the build can die, and so that Android 17's 30 GB analysis still completes.

## Disk: ext4 inside a VHDX on the spare drive

[`scripts/windows/make-build-disk.ps1`](../scripts/windows/make-build-disk.ps1) (elevated):

1. `diskpart`: create an expanding VHDX (default 600 GB maximum) on the spare drive.
2. `wsl --mount --vhd … --bare`, then identify the new block device by diffing `lsblk` before and after.
   - Only that device is formatted.
   - Physical Windows drives are never exposed to WSL as block devices.
3. `mkfs.ext4 -L lineage -m 0` on it.
4. `wsl --mount --vhd … --name lineage`, which gives `/mnt/wsl/lineage` in every WSL distro.

Not NTFS or the 9p mount: Android's build does millions of small-file operations. Not the nearly full NVMe either. The trade-off is that an HDD makes the first build slow.

The attachment does not survive a reboot or `wsl --shutdown`. Re-attach with [`attach-build-disk.ps1`](../scripts/windows/attach-build-disk.ps1).

## Docker sees it as a raw device, not a path

A bind mount of `/mnt/wsl/lineage` into a Docker Desktop container **does not reach the disk**. The daemon has its own mount namespace, and there the path is an empty directory on Docker's own 127 MB disk. Verified with `df`: `/dev/sde 127M` instead of the 590 GB disk.

All WSL distros and Docker Desktop share one VM kernel, so the VHDX is visible to the daemon as a block device. A `local`-driver volume mounts it directly:

```sh
docker volume create --driver local --opt type=ext4 --opt device=/dev/sdX --opt o=noatime lineage-build
```

[`build/ensure-volume.sh`](../build/ensure-volume.sh) finds the device by filesystem label and recreates the volume when the letter moves. Run it before every use: a volume pointing at a stale `/dev/sdX` would mount some other disk.

## Memory: Soong analysis needs zram

**Android 17's Soong analysis does not fit in this VM.** Measured on this tree:
- `soong_build` alone needs over 30 GB: about 8 GB in RAM plus 26 GB swapped. AOSP's stated minimum is 64 GB of RAM.
- A heap profile taken inside the cap showed module variants at about half the live heap and build actions at most of the rest, still growing when the ninja file was being written.
- **Nothing within reach of a memory cap gets it under 12 GB:**
  - incremental analysis is already off with Kati
  - `GOMEMLIMIT` only slows growth
  - pruning a fifth of the `Android.bp` files and dropping Windows host variants saved little
  - Android 17's on-demand variants are forced off with Kati, and forcing them on broke Kati
- **Disk swap froze the whole VM**: every Go GC cycle walks the entire heap, so paging it through a VHDX stalls everything. At the cgroup limit without swap, the kernel evicts file cache for minutes instead of OOM-killing.

**What works: zram as the VM's only swap.**
- [`build/zram.sh`](../build/zram.sh) `on` loads the zram module (the WSL kernel ships it; there is no zswap), makes a 40 GB zram device the only swap, and swaps the VHDX swap off. This is runtime only, so run it again after any VM restart.
- lzo-rle compresses Soong's heap about 4:1.
- Analysis of the full tree takes about 25 minutes and completes; `m nothing` takes about 28.

[`build/build.sh`](../build/build.sh) detects zram and switches to:
- **`--memory=8g`, `--memory-swap=44g`.** The 36 GiB swap share stays below the zram total; peak use measured was 26 GB.
- **`GOGC=30`.** Every page of the heap ends up swapped, so trading GC CPU for a smaller heap pays.
- **`-j5`.** siso holds about 5 GB of graph, and every javac gets a 4 GB heap. At `-j10` the Java-heavy part thrashed (57% full memory stall for an hour); at `-j5` stall stayed under 1%.
- **Two watchdogs.**
  - Kill on sustained cgroup memory pressure (`PSI_KILL`, 45% "full" for 60 s; healthy zram runs sit at 8–20%).
  - Kill when the VM's own `MemAvailable` stays under 700 MB for 30 s. `/proc/meminfo` inside the container is the VM's.
- A memory trace (cgroup usage plus the three largest processes, every 10 s) next to each build log.

Without zram it falls back to `--memory=12g` with no swap, which cannot finish analysis but cannot take the VM down either.

Always set:
- **`NINJA_HIGHMEM_NUM_JOBS=1`.** Soong sizes its highmem pool from `/proc/meminfo` (`build/soong/ui/build/config.go`, `HighmemParallel()`), which inside a container still shows the whole VM.
- `--cpus=10`, low CPU shares and `nice`.
- `WITH_DEXPREOPT=false` for development builds.
- ccache on the same disk.

**Build-system fixes this needed** (our `patches/build_*`):
- **blueprint:** `SourceRootDirAllowed` sorted the shared prefix list on every lookup from parallel parse goroutines. With a long prune list, the race made skipped files get parsed. It now sorts once.
- **blueprint:** optional periodic heap dumps (`SOONG_PERIODIC_MEMPROFILE`), because `--memprofile` is only written when analysis finishes.
- **soong:** forward `GOMEMLIMIT`, `GOGC` and `GODEBUG` to `soong_build`, which otherwise runs with an empty environment.
- **soong:** give the KSP client kotlinc's 8 GB heap. The JVM default inside the cgroup, a quarter of 8 GiB, ran out on SystemUI.
- **make:** `DISABLE_HOST_CROSS_WINDOWS=true` drops the Windows host variants.

**Pruning.** [`build/soong-prune.py`](../build/soong-prune.py) writes the device's `soong-prune.mk` (`PRODUCT_SOURCE_ROOT_DIRS`). It skips CTS, automotive, Qualcomm and test trees, splitting directories until nothing kept still references a pruned module. Three things to know about blueprint's matching:
- Prefixes are plain string prefixes, so directories need a trailing slash.
- A namespace-declaring `Android.bp` must never be pruned on its own.
- Implicit module-type dependencies (a tradefed suite's `<name>-tradefed-tests`) and `":name"` source references must count as uses.

**If the VM dies mid-build:**
- siso records steps as done whose output never reached the disk. Delete everything in `out/` written in the minutes before the crash.
- siso skips rewriting a response file it believes is unchanged, so crash-truncated `.rsp` files come back empty: links fail with "undefined symbol: main" and archives come out empty. Delete every `.rsp` under `out/`. That re-runs every step that uses one, about 6 hours here.

On 2026-11-12 a Windows Update install of WSL 3.0.5.0 killed the VM mid-build. Pause updates while a long build runs.

[`build/sync.sh`](../build/sync.sh) runs `repo init` for `lineage-24.0` (`--depth=1 --git-lfs`), copies [`build/local_manifests/cancunf.xml`](../build/local_manifests/cancunf.xml) in, and syncs with 4 jobs. It runs at idle I/O priority so it doesn't swamp the HDD.

## Our changes to synced trees

Our changes live as `git format-patch` files in [`patches/<project>/`](../patches). [`build/apply-patches.sh`](../build/apply-patches.sh) re-applies them on a local `lineage` branch on top of the synced revision, so a later `repo sync` can move the base. Run it after every sync and before building.

The first patch replaces YAAP's product with `lineage_cancunf`. The rest port YAAP's June trees to LineageOS 24, each found by an actual build failure:

| Patch | What and why |
|---|---|
| device 0002, vendor 0001 | `hardware/mediatek/libaedv` is no longer its own Soong namespace |
| device 0003, vendor 0002 | the MediaTek `libmnl` blob clashes with `external/libmnl` (now `vendor_available`): renamed `libmnl_mtk` with `FIX_SONAME`, `mnld` relinked |
| device 0004 | keep the device USB gadget rc (`mediatek_gadget.use_custom_usb_gadget_rc`) |
| device 0005 | touch HAL ported from HIDL `vendor.lineage.touch@1.0` to AIDL |
| device 0006, vendor 0003 | `libformatter` clashes with a host Rust library (renamed `libformatter_mtk`); `libladder` and `wlan_assistant` now come from `hardware/mediatek` |
| device 0007 | Soong pruning (`soong-prune.mk`) |
| device 0008 | export the `power-libperfmgr` Soong namespace |
| device 0009, 0012 | MotoActions on the LineageOS SDK instead of YAAP framework classes; the pocket state now comes from the proximity sensor in the app; two doze strings LineageOS dropped |
| device 0010, 0011 | sepolicy: drop a type `sepolicy_vndr` now declares; label the camera app list with LineageOS's `camera2_extensions_prop` instead of a Qualcomm-only type |
| device 0013 | FCM target level 6 to 7: Android 17 has no level-6 framework matrix, so the OTA's VINTF check failed |
| device 0014, vendor 0004 | `libsink-mtk` (IMS video calls) gets LineageOS's `libaudioclient_shim` for an `AudioTrack` constructor Android 17 removed |
| DisplayFeatures 0001 | YAAP-only DC-dimming settings keys defined in the app (cancunf has no DC-dimming node) |

Binary edits to vendor blobs (renames, `patchelf`) are not stored as patches, because this repo carries no proprietary files. `apply-patches.sh` performs them after the vendor patches, matching what `extract-files.py` would now produce. `BRANCH=<name>` lets a scratch worktree verify the series without moving the live branch: the whole series reproduces the built trees byte for byte.

Checked before writing it:
- **No kernel is compiled.** `TARGET_NO_KERNEL_OVERRIDE := true` makes LineageOS skip its whole `kernel.mk` logic, and the tree's own rule copies the prebuilt `Image.gz`.
- **The IMS app is already patched.** The vendor `ImsService.apk` has zero `TelephonyMetrics` references and declares `mediatek-ims-base`/`mediatek-ims-oem-plugin`, which is YAAP's patch 0006.
