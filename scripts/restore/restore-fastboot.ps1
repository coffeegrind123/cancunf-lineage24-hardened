# Restore the moto g54 5G (cancunf, XT2343-2) firmware partitions from a full dump, in bootloader (fastboot) mode. Bootloader must be unlocked.
#
#   powershell -ExecutionPolicy Bypass -File restore-fastboot.ps1 -BackupDir D:\g54-backup            # dry run
#   powershell -ExecutionPolicy Bypass -File restore-fastboot.ps1 -BackupDir D:\g54-backup -Go        # flash firmware set, both slots
#   ... -Go -Only boot_a,vendor_boot_a                                      # just these partitions
#   ... -Go -Wipe                                                           # also erase userdata+metadata (factory reset)
#
# Layout expected under -BackupDir (what scripts/backup/device-dump.sh produces, plus stock\):
#   dump\images\<partition>.img + SHA256SUMS   raw dd images taken on the phone
#   stock\boot_a.img + SHA256SUMS              factory boot_a (a dump taken while rooted has Magisk in boot_a)
#
# Partitions that hold per-device data (IMEI, calibration, keys: nvram, nvdata,
# persist, proinfo, ...) and the preloader LUNs are NOT written here. Motorola's
# bootloader refuses most of them; restore those from rooted Android with
# device-restore.sh, and only when they are actually damaged.

param(
    [Parameter(Mandatory = $true)][string]$BackupDir,
    [switch]$Go,
    [switch]$Wipe,
    [string[]]$Only,
    [string]$Fastboot = "fastboot.exe"
)

$ErrorActionPreference = "Stop"

$Images = Join-Path $BackupDir "dump\images"
$StockBoot = Join-Path $BackupDir "stock\boot_a.img"
$Expected = @{ product = "cancunf"; sku = "XT2343-2" }

# Firmware partitions, flashed for both slots. Order follows Motorola's
# flashfile.xml (bootloader chain first, vbmeta before the images it signs,
# super last).
$AbParts = @(
    "lk", "tee", "mcupm", "pi_img", "sspm", "dtbo", "logo", "spmfw", "scp",
    "vbmeta", "vbmeta_system", "md1img", "dpm", "gz", "vcp", "gpueb",
    "tzapp", "connsys_bt", "connsys_wifi", "connsys_gnss",
    "boot", "vendor_boot"
)
$Plan = @()
foreach ($p in $AbParts) {
    $Plan += "${p}_a"
    $Plan += "${p}_b"
}
$Plan += "super"

function Fail([string]$msg) {
    Write-Host "FATAL: $msg" -ForegroundColor Red
    exit 1
}

function Run-Fastboot([string[]]$fbArgs) {
    # fastboot reports everything on stderr; under "Stop", PS 5.1 turns each
    # stderr line of a native command into a terminating error. Success is
    # judged by the exit code instead.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & $Fastboot @fbArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    return @{ code = $code; text = ($out -join "`n") }
}

function Get-Var([string]$name) {
    $r = Run-Fastboot @("getvar", $name)
    $m = [regex]::Match($r.text, "(?m)^\(?bootloader\)?\s*${name}:\s*(.+)$")
    if (-not $m.Success) {
        $m = [regex]::Match($r.text, "(?m)^${name}:\s*(.+)$")
    }
    if ($m.Success) {
        return $m.Groups[1].Value.Trim()
    }
    return ""
}

function Source-For([string]$part) {
    # The dump's boot_a carries Magisk; restore the factory image instead.
    if ($part -eq "boot_a") {
        return (Resolve-Path $StockBoot).Path
    }
    return (Join-Path (Resolve-Path $Images).Path "$part.img")
}

if (-not (Get-Command $Fastboot -ErrorAction SilentlyContinue)) { Fail "fastboot not found: $Fastboot (pass -Fastboot)" }
if (-not (Test-Path (Join-Path $Images "SHA256SUMS"))) { Fail "no SHA256SUMS in $Images" }
if (-not (Test-Path $StockBoot)) { Fail "missing $StockBoot" }

if ($Only) {
    $unknown = $Only | Where-Object { $Plan -notcontains $_ }
    if ($unknown) { Fail ("not in the fastboot plan: " + ($unknown -join ", ") + ". Unique/preloader partitions go through device-restore.sh.") }
    $Plan = $Plan | Where-Object { $Only -contains $_ }
}

# 1. Verify every image against the manifest written on the phone at dump time.
$sums = @{}
foreach ($line in Get-Content (Join-Path $Images "SHA256SUMS")) {
    $f = $line -split "\s+", 2
    if ($f.Count -eq 2) { $sums[$f[1].Trim()] = $f[0].ToLower() }
}
$stockSum = (Get-Content (Join-Path $BackupDir "stock\SHA256SUMS") | Where-Object { $_ -match "boot_a\.img" }) -split "\s+" | Select-Object -First 1

Write-Host "Verifying $($Plan.Count) images..."
foreach ($p in $Plan) {
    $src = Source-For $p
    if (-not (Test-Path $src)) { Fail "missing image $src" }
    $want = if ($p -eq "boot_a") { $stockSum } else { $sums["$p.img"] }
    if (-not $want) { Fail "no manifest hash for $p" }
    $got = (Get-FileHash -Algorithm SHA256 $src).Hash.ToLower()
    if ($got -ne $want.ToLower()) { Fail "$p hash mismatch: $got != $want" }
    Write-Host ("  ok  {0,-18} {1}" -f $p, $src)
}

# 2. Device identity and lock state.
$devices = (Run-Fastboot @("devices")).text
if ($devices -notmatch "fastboot") { Fail "no device in fastboot mode" }
$product = Get-Var "product"
$sku = Get-Var "sku"
$state = Get-Var "securestate"
Write-Host "Device: product=$product sku=$sku securestate=$state"
if ($product -ne $Expected.product) { Fail "product is '$product', expected $($Expected.product)" }
if ($sku -ne $Expected.sku) { Fail "sku is '$sku', expected $($Expected.sku)" }
if ($state -notmatch "unlocked") { Fail "bootloader is not unlocked ($state); flashing would be refused" }

if (-not $Go) {
    Write-Host ""
    Write-Host "DRY RUN. Would flash, in order:" -ForegroundColor Yellow
    $Plan | ForEach-Object { Write-Host "  $_" }
    if ($Wipe) { Write-Host "  erase userdata, erase metadata" }
    Write-Host "  set-active a, reboot"
    Write-Host "Re-run with -Go to write."
    exit 0
}

# 3. Flash.
foreach ($p in $Plan) {
    $src = Source-For $p
    Write-Host "flash $p <- $src"
    $r = Run-Fastboot @("flash", $p, $src)
    Write-Host $r.text
    if ($r.code -ne 0) { Fail "flash $p failed" }
}

if ($Wipe) {
    foreach ($p in @("userdata", "metadata")) {
        $r = Run-Fastboot @("erase", $p)
        Write-Host $r.text
        if ($r.code -ne 0) { Fail "erase $p failed" }
    }
}

$r = Run-Fastboot @("--set-active=a")
Write-Host $r.text
if ($r.code -ne 0) { Fail "set-active a failed" }

Write-Host "Done. Rebooting." -ForegroundColor Green
Run-Fastboot @("reboot") | Out-Null
