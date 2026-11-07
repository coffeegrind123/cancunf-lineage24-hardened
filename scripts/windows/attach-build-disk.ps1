# Re-attach the build disk after a reboot or `wsl --shutdown` (attachments do
# not persist). Run elevated. Harmless if it is already attached.
#
#   powershell -ExecutionPolicy Bypass -File attach-build-disk.ps1 -VhdPath D:\lineage\build.vhdx

param(
    [string]$VhdPath = "D:\lineage\build.vhdx",
    [string]$Name = "lineage",
    [string]$Distro = "Debian",
    [string]$Log = (Join-Path $PSScriptRoot "attach-build-disk.log")
)

Start-Transcript -Path $Log -Force | Out-Null
try {
    if (-not (Test-Path $VhdPath)) { throw "$VhdPath not found" }
    wsl.exe --mount --vhd $VhdPath --name $Name
    Write-Output "wsl --mount exit $LASTEXITCODE (nonzero is expected if already attached)"
    wsl.exe -d $Distro -u root -- df -h "/mnt/wsl/$Name"
    Write-Output "OK"
} catch {
    Write-Output ("FAILED: " + $_)
}
Stop-Transcript | Out-Null
