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

## adb over Wi-Fi

Use it when the cable is out, or to keep adb across an install without touching the phone. It works only while Android runs: recovery has no network, and a crash-looping system never brings Wi-Fi up, so those still need USB or `debug/sdlog` ([09-first-install.md](09-first-install.md#logging-without-adb-debugsdlog)). The phone and the Windows PC must be on the same network; the Windows adb server makes the connection.

### Wireless debugging (Android 11+, no cable)

1. On the phone: Settings → System → Developer options → **Wireless debugging** on. Accept "Allow on this network".
2. Find it from Linux through the Windows server's mDNS discovery:

   ```sh
   adb -H host.docker.internal mdns services
   # adb-<serial>-<id>   _adb-tls-connect._tcp   <phone-ip>:<port>
   adb -H host.docker.internal connect <phone-ip>:<port>
   adb -H host.docker.internal devices -l
   ```

3. If `connect` fails with an authentication error, pair once: Wireless debugging → "Pair device with pairing code", then `adb -H host.docker.internal pair <ip>:<pairing-port> <code>` (the pairing port differs from the connect port), and connect again. On our phone pairing wasn't needed: the key already authorised over USB was accepted.

The port is random and changes whenever the phone reboots or wireless debugging is toggled; Android may also turn wireless debugging off after a reboot or a network change. After the reboot that finishes an update, re-run `mdns services` and `connect`. With both USB and Wi-Fi attached, pick one with `-s <serial>` or `-s <ip>:<port>`.

### `adb tcpip` (needs the cable once)

With the phone on USB: `adb -H host.docker.internal tcpip 5555`, unplug, `adb -H host.docker.internal connect <phone-ip>:5555`. No pairing; the USB key is reused. adbd goes back to USB-only at the next reboot.

### Caveats

- On battery, "Stay awake" (`stay_on_while_plugged_in`) doesn't hold, so the phone locks after the screen timeout; UI steps driven with `uiautomator`/`input` need it unlocked.
- Wireless debugging exposes adbd on the LAN (TLS, keys still checked). Turn it off on untrusted networks.
