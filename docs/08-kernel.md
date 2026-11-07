# Kernel: our own cancunf kernel

**Repo:** [coffeegrind123/kernel_motorola_cancunf](https://github.com/coffeegrind123/kernel_motorola_cancunf), a fork of [cyberknight777/dragonheart_kernel_motorola_cancunf](https://github.com/cyberknight777/dragonheart_kernel_motorola_cancunf), branch `android12-5.10`.

## Why

The ROM currently ships YAAP's prebuilt `5.10.240-DragonHeart` (built 2026-05-05). Kernel fixes then depend on one community maintainer publishing a prebuilt. Building it ourselves lets every release:
- carry current Android kernel security fixes
- carry current upstream 5.10 stable releases
- add GrapheneOS's kernel hardening where it applies

## Facts (checked 2026-11-07)

**Upstream.** Linux 5.10 is a maintained longterm series: kernel.org released **5.10.274** on 2026-11-06 and does not mark it end-of-life. DragonHeart is at **5.10.240**, 34 stable releases behind. The projected end-of-life date has not been verified here; check kernel.org's releases page each cycle.

**Google.** `kernel/common` branches `android12-5.10` and `android12-5.10-lts` are active (last commits 2026-11-04). They carry the monthly Android kernel security fixes and Google's merges of 5.10 stable.

**DragonHeart.**
- Full source for this phone, including MediaTek's drivers: `drivers/misc/mediatek` (123 entries) with `ccci_util` (modem), `drivers/soc/mediatek`, `drivers/gpu/mediatek`.
- Device config `build.config.cancunf` and build script `kramel.sh`.
- It already merges Google's GKI releases in dated branches (`20250916/android12-5.10`, and others).

**Modules.** We build the kernel **and all modules**, so Google's frozen module interface (KMI) does not constrain changes. First check: compare the modules we build against the prebuilt's 173 `vendor_dlkm` modules and its `vendor_boot` dlkm cpio, to catch any binary-only module.

**GrapheneOS.** It has no 5.10 kernel any more. Its current kernels are Pixel 6.1 and 6.18.
- [`GrapheneOS/kernel_common-6.1`](https://github.com/GrapheneOS/kernel_common-6.1), branch `17`, carries **93 commits** on top of `android14-6.1-lts` at Linux 6.1.182.
- 67 of those are GrapheneOS's own work; the rest are backported fixes.
- The boundary is the first commit not committed by Daniel Micay, the `Merge 6.1.182 into android14-6.1-lts` commit, and the list is kept locally.
- Everything has to be backported from 6.1 to 5.10.

**LineageOS.** No kernel hardening. It offers build integration: `vendor/lineage/build/tasks/kernel.mk` can build the kernel from `TARGET_KERNEL_SOURCE` inside the ROM build, instead of the current `TARGET_NO_KERNEL_OVERRIDE` prebuilt route.

## GrapheneOS kernel hardening, sorted for 5.10

**A. Config hardening.** Mostly portable. Check that each option exists in 5.10.

| Change | 5.10 note |
|---|---|
| `INIT_ON_FREE_DEFAULT_ON`, zero memory in early boot | `init_on_free` exists since 5.3 |
| BPF JIT hardening by default; disable `BINFMT_MISC`, `LDISC_AUTOLOAD`, TIPC, `HIBERNATION`, memory hotplug, POSIX mqueue; restrict sysrq | config/defaults |
| `DEBUG_CREDENTIALS`, `DEBUG_SG` | present in 5.10 |
| lockdown LSM, confidentiality mode | present since 5.4 |
| forced module signing, sha256 | feasible because we build every module |
| max mmap entropy; arm64 stack entropy from mmap entropy | portable |
| `RANDOMIZE_KSTACK_OFFSET_DEFAULT` | upstream since 5.13. **Check whether `android12-5.10` backported it**; if not, port it |
| `ARM64_BTI_KERNEL` | present since 5.8, but the Cortex-A78/A55 cores are ARMv8.2 and lack BTI, so it does nothing here |
| `RANDSTRUCT_FULL` | clang randstruct arrived in 5.19; 5.10 only has the GCC plugin. **Skip** (we build with clang) |
| 48-bit address space plus higher mmap bits | changes the user VA layout; needs testing with vendor GPU/camera blobs. Goes with `FLAG_COMPAT_VA_39_BIT` (C) |

**B. Self-contained code hardening.** Backport each one and test it.
- slub random canaries (`fb40683df3`), including canaries on bulk-alloc failure (`e4c76d08d7`)
- `__ro_after_init` and `__read_only` markings, read-only sysctl constants
- randomized lower bits of `brk` and of the argument block; `brk` gap guarantee
- page-sanitization verification
- `kmem_cache_free` with the wrong cache becomes a bug
- kfence respects `BUG_ON_DATA_CORRUPTION`

**C. Needs GrapheneOS userspace.** Port together with the matching framework feature.
- **SELinux `tsec_flags`:** restricting dynamic code execution, blocking ptrace, zygote context caching. These back GrapheneOS's per-app exploit-protection settings.
- **Process attribute flags:** `DISABLE_HARDENED_MALLOC` (the kernel side of hardened_malloc opt-outs for MediaTek vendor processes), `OVERRIDE_PREV_SELINUX_CTX_TO_INIT`, `FLAG_COMPAT_VA_39_BIT`.
- **`deny_new_usb`** (also covering USB gadgets): the kernel side of GrapheneOS's USB-C port toggle.
- **Android "paranoid" socket check:** the kernel side of the Network permission toggle.

**D. Skip.** Pixel, virtualization, x86, UEFI, Tegra, build scripts, ABI updates, SVE for protected guests. Also `tcpm` alt-mode options, unless this phone's USB-C stack uses `tcpm`.

**E. Backported upstream fixes** (about 26, for example blk-crypto, HID, f_midi, fscrypt, RFCOMM, exec, procfs). For each one, check whether 5.10 stable or `android12-5.10` already has it. Backport the ones that apply and are missing.

## Building

- In the capped build container on the build disk (CLAUDE.md exception, extended to this kernel on 2026-11-07).
- Use DragonHeart's `build.config.cancunf` with the clang toolchain it pins.
- **Outputs:** `Image.gz`, `dtb`, `dtbo.img`, `vendor_dlkm` modules, and the `vendor_boot` dlkm cpio. These go into our own fork of `device_motorola_cancunf-kernel`, which the local manifest then points at instead of YAAP's.
- Building in-tree through LineageOS `kernel.mk` is the later alternative.

**First milestone:** our build of unmodified DragonHeart. Its module set must match the prebuilt's, and it must boot to the same state as the prebuilt. Only after that come the merges and the hardening.

## Each release cycle

This is part of step 3 in [07-maintenance.md](07-maintenance.md).

1. Merge Google `android12-5.10`, bringing the security fixes plus the 5.10 stable merges.
2. Pull in DragonHeart's new device commits.
3. Re-check GrapheneOS `kernel_common-6.1` (and 6.18) for new hardening commits since the last recorded head, kept in [`ported.json`](../ported.json) under `kernel`, and sort them into A to E.
4. Build, then test on the phone: boot, modem/IMS, Wi-Fi, Bluetooth, camera, GPU, fingerprint, charging, suspend and resume. Check `dmesg` for hardening trips in MediaTek drivers.

## After 5.10's end of life

- Google's `android12-5.10` continues on Google's schedule.
- The Civil Infrastructure Platform maintains a super-long-term `linux-cip` 5.10. Its end date and how well it merges with Android's kernel are **not verified**; check that before relying on it.
- Moving to a newer kernel series is not realistic: MediaTek's 5.10 vendor drivers would all have to be ported.
