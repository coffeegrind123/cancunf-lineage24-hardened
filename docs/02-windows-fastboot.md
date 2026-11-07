# Windows fastboot with a Motorola bootloader

## Symptom

- In Android, adb works: interface `22B8:2E81` binds WinUSB on its own via Microsoft OS descriptors.
- After `adb reboot bootloader`, the bootloader interface `22B8:2E80` shows up as **"Android", status Error**: no driver.

## Fix

1. Install WinUSB for that interface with [Zadig](https://zadig.akeo.ie): Options → List All Devices → "Android" (`22B8 2E80`) → WinUSB → Install.
2. Device Manager now says OK, **but `fastboot devices` is still empty.**
   - `fastboot.exe` (AdbWinUsbApi) enumerates devices by the Android USB interface GUID `{F72FE0D4-CBCB-407D-8814-9ED673D0DD6B}`.
   - Zadig's INF registers a random `DeviceInterfaceGUIDs` value instead (it was `{B71350B3-…}` here).
3. Run [`scripts/windows/fix-fastboot-guid.ps1`](../scripts/windows/fix-fastboot-guid.ps1) elevated. It rewrites `DeviceInterfaceGUIDs` under `HKLM\SYSTEM\CurrentControlSet\Enum\USB\VID_22B8&PID_2E80\<serial>\Device Parameters` and restarts the device with `pnputil /restart-device`. `fastboot devices` then lists the phone.

Motorola's or Google's signed driver packages are the alternative. The GUID route needs no further downloads.

## Driving it from WSL or Docker

- **adb:** run the Windows adb server and connect from Linux with `adb -H host.docker.internal -P 5037 …` (Docker Desktop). The Linux client talks to the Windows server, which owns the USB device.
- **fastboot** has no server, so run `fastboot.exe` on Windows.
- **PowerShell 5.1 quirk:** fastboot writes everything to stderr. Under `$ErrorActionPreference = "Stop"`, PS 5.1 turns each stderr line of a native command into a terminating error. Judge success by `$LASTEXITCODE` (see `Run-Fastboot` in `restore-fastboot.ps1`).
