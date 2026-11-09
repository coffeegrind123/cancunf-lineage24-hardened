# Unlock and root

## Unlock

1. Turn on Developer options → OEM unlocking. `sys.oem_unlock_allowed` goes to `1`.
2. In bootloader mode, run `fastboot oem get_unlock_data`. Join the lines and request the code at Motorola's [bootloader unlock page](https://en-us.support.motorola.com/app/standalone/bootloader/unlock-your-device-b).
   - `fastboot flashing unlock` without a code is refused: `A unlock code may be required`.
3. Run `fastboot oem unlock <code>` and confirm on the phone.
   - Result: `securestate: flashing_unlocked`, `iswarrantyvoid: yes`, userdata wiped.
   - The unlock data contains the serial, so keep it private.

## `Preflash validation failed` with Magisk v28 and later

Observed on bootloader `MBM-3.1-cancunf_g_vext` with build `12-7-6`:

| Image flashed to `boot_a` | Result |
|---|---|
| stock `boot.img` | OKAY |
| Magisk **v31.1**-patched | `Preflash validation failed` |
| v31.1-patched, AVB hash footer rebuilt (`avbtool add_hash_footer`, original salt and properties) | `Preflash validation failed` |
| Magisk **v27.0**-patched | OKAY, boots rooted |

**What this rules out:** the bootloader is not checking the AVB footer's consistency. v31.1's footer described the original image size and hash; the rebuilt footer was internally consistent; and v27.0's footer also describes the original image. The bootloader still told them apart.

**Visible difference:** v31.1 leaves a ramdisk of 1,118,033 bytes, v27.0 one of 1,511,163 bytes. The v31.1 ramdisk is smaller than stock's (1,380,092 bytes).

**Likely explanation:** [PixelOS's cancunf install guide](https://github.com/PixelOS-AOSP/official_devices/blob/seventeen/API/instructions/cancunf.md) says Motorola's bootloader runs a timestamp check on images flashed from bootloader-mode fastboot, and that flashing from **fastbootd** (`fastboot reboot fastboot`; confirm with `fastboot getvar is-userspace` → `yes`) avoids `Preflash validation failed`. This was not tested here; v27.0 may simply have passed the timestamp check.

Other Motorola owners report the same split: [Magisk #8389](https://github.com/topjohnwu/Magisk/issues/8389), and [#8373](https://github.com/topjohnwu/Magisk/issues/8373) on an XT2343-6.

**Route that works:**
1. Patch the matching stock `boot.img` with **Magisk v27.0**. On-device patching works without the app: push `boot_patch.sh`, `util_functions.sh`, `stub.apk` and the `libmagisk*` binaries, then run it as the shell user.
2. Flash it to `boot_a`.
3. Install the v27.0 app.
4. If you want a newer Magisk, update from inside the app with **Direct install**, which avoids fastboot entirely.

There is no `fastboot boot` (temporary boot), so root has to be flashed. Try fastbootd first before falling back to v27.0.

## Shell root prompt

The first `su` from `adb shell` was denied without a dialog. The prompt had timed out and stored a deny. Fix: Magisk → Superuser → enable **Shell**.
