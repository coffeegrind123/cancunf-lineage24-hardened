# Make Google's fastboot.exe see a Motorola bootloader interface that was bound
# to WinUSB with Zadig. Run elevated.
#
# fastboot.exe (AdbWinUsbApi) enumerates devices by the Android USB interface
# GUID {F72FE0D4-CBCB-407D-8814-9ED673D0DD6B}. Zadig's generic WinUSB INF
# registers a random DeviceInterfaceGUIDs value instead, so the driver shows
# "OK" in Device Manager while `fastboot devices` stays empty.
#
#   powershell -ExecutionPolicy Bypass -File fix-fastboot-guid.ps1                 # Motorola bootloader 22B8:2E80
#   powershell -ExecutionPolicy Bypass -File fix-fastboot-guid.ps1 -HardwareId "USB\VID_xxxx&PID_yyyy"

param(
    [string]$HardwareId = "USB\VID_22B8&PID_2E80"
)

$AndroidGuid = "{F72FE0D4-CBCB-407D-8814-9ED673D0DD6B}"
$devs = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "$HardwareId\*" }
if (-not $devs) {
    Write-Output "No present device matches $HardwareId. Put the phone in bootloader mode and install WinUSB with Zadig first."
    exit 1
}

foreach ($d in $devs) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)\Device Parameters"
    $before = (Get-ItemProperty $key -ErrorAction SilentlyContinue).DeviceInterfaceGUIDs -join ","
    Set-ItemProperty -Path $key -Name DeviceInterfaceGUIDs -Type MultiString -Value @($AndroidGuid)
    Write-Output "$($d.InstanceId): $before -> $AndroidGuid"
    pnputil /restart-device "$($d.InstanceId)"
}
