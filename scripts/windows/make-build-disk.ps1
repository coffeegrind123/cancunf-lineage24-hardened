# Create an ext4 build disk inside an expanding VHDX and mount it in WSL at
# /mnt/wsl/<Name>. Run elevated (diskpart and wsl --mount need it).
#
# Only the block device that appears after attaching the new VHDX is
# formatted; it is found by diffing lsblk before and after the attach.
#
#   powershell -ExecutionPolicy Bypass -File make-build-disk.ps1 -VhdPath D:\lineage\build.vhdx

param(
    [string]$VhdPath = "D:\lineage\build.vhdx",
    [int]$SizeMB = 614400,
    [string]$Name = "lineage",
    [string]$Distro = "Debian",
    [string]$Log = (Join-Path $PSScriptRoot "make-build-disk.log")
)

Start-Transcript -Path $Log -Force | Out-Null
try {
    New-Item -ItemType Directory -Force -Path (Split-Path $VhdPath) | Out-Null
    if (-not (Test-Path $VhdPath)) {
        $dp = Join-Path $env:TEMP "mkvhd.txt"
        "create vdisk file=`"$VhdPath`" maximum=$SizeMB type=expandable" | Out-File -Encoding ascii $dp
        diskpart /s $dp
        if (-not (Test-Path $VhdPath)) { throw "diskpart did not create $VhdPath" }
    }

    $before = (wsl.exe -d $Distro -u root -- lsblk -dn -o NAME) -join " "
    wsl.exe --mount --vhd $VhdPath --bare
    Start-Sleep -Seconds 3
    $after = wsl.exe -d $Distro -u root -- lsblk -dn -o NAME,SIZE
    $new = $after | Where-Object { ($_ -split "\s+")[0] -notin ($before -split " ") } | Select-Object -First 1
    if (-not $new) { throw "new disk not found after attach" }
    $dev = "/dev/" + ($new -split "\s+")[0]
    Write-Output "new disk: $new"

    $fs = wsl.exe -d $Distro -u root -- blkid -o value -s TYPE $dev
    if ($fs -ne "ext4") {
        wsl.exe -d $Distro -u root -- mkfs.ext4 -F -L $Name -m 0 $dev
        if ($LASTEXITCODE -ne 0) { throw "mkfs.ext4 failed" }
    }

    wsl.exe --unmount $VhdPath
    wsl.exe --mount --vhd $VhdPath --name $Name
    if ($LASTEXITCODE -ne 0) { throw "named mount failed" }
    wsl.exe -d $Distro -u root -- df -h "/mnt/wsl/$Name"
    Write-Output "OK"
} catch {
    Write-Output ("FAILED: " + $_)
}
Stop-Transcript | Out-Null
