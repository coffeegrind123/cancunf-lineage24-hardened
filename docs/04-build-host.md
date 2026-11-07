# Build host: Windows + WSL2 + Docker Desktop

The host is a Ryzen 9 3900X with 32 GB of RAM. The WSL VM is capped at 22 GB of memory and 16 GB of swap, and is shared with other workloads. The NVMe is nearly full; a 10 TB HDD has space. An unconstrained Android build in that VM once exhausted memory and swap and took Docker Desktop down. The setup below is built so that only the build can die.

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

## The build container is capped

[`build/build.sh`](../build/build.sh):

- `--memory=12g --memory-swap=24g --cpus=10`, low CPU shares and `nice`. On OOM the kernel kills the build, not the VM.
- **`NINJA_HIGHMEM_NUM_JOBS=1`.** Soong sizes its highmem pool from `/proc/meminfo` (`build/soong/ui/build/config.go`, `HighmemParallel()`), which inside a container still shows the whole VM. Without the pin it would schedule for 22 GB.
- `-j10`, `WITH_DEXPREOPT=false` for development builds, ccache on the same disk.
- When the build ends, it logs the cgroup's `memory.peak`, `memory.swap.peak` and OOM events, so the cap can be tuned from measurements.

[`build/sync.sh`](../build/sync.sh) runs `repo init` for `lineage-24.0` (`--depth=1 --git-lfs`), copies [`build/local_manifests/cancunf.xml`](../build/local_manifests/cancunf.xml) in, and syncs with 4 jobs. It runs at idle I/O priority so it doesn't swamp the HDD.

## Our changes to synced trees

Our changes live as `git format-patch` files in [`patches/<project>/`](../patches). [`build/apply-patches.sh`](../build/apply-patches.sh) re-applies them on a local `lineage` branch on top of the synced revision, so a later `repo sync` can move the base. Run it after every sync and before building.

The first patch replaces YAAP's product with `lineage_cancunf`.

Checked before writing it:
- **No kernel is compiled.** `TARGET_NO_KERNEL_OVERRIDE := true` makes LineageOS skip its whole `kernel.mk` logic, and the tree's own rule copies the prebuilt `Image.gz`.
- **The IMS app is already patched.** The vendor `ImsService.apk` has zero `TelephonyMetrics` references and declares `mediatek-ims-base`/`mediatek-ims-oem-plugin`, which is YAAP's patch 0006.
