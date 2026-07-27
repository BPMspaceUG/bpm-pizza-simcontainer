#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a ready-to-use BPM Pizza Sim WSL distro in one command.

.DESCRIPTION
    Downloads the prebuilt rootfs from the latest GitHub release, imports it as
    a new WSL distro next to any existing ones, runs the bootstrap (which pulls
    the .env from the protected endpoint) and drops you into a shell.

.PARAMETER BasicAuth
    Credentials for the .env endpoint in "user:password" form. If omitted, the
    script asks once; press Enter to skip. Use -NoEnv to skip without asking.

.PARAMETER Name
    Distro name. Defaults to "pizza-sim". If it already exists, a numeric
    suffix is appended (pizza-sim-2, pizza-sim-3, ...).

.PARAMETER NoEnv
    Skip the .env fetch entirely. The distro comes up with an empty .env.

.PARAMETER Rootfs
    Use a local rootfs tarball instead of downloading the release asset.

.EXAMPLE
    create_debian user:password

.EXAMPLE
    create_debian -NoEnv

.EXAMPLE
    create_debian user:password -Name pizza-sim-training

.EXAMPLE
    create_debian -Rootfs C:\build\rootfs.tar -NoEnv
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$BasicAuth,

    [string]$Name = "pizza-sim",

    [switch]$NoEnv,

    [string]$Rootfs,

    [string]$Repo = "BPMspaceUG/bpm-pizza-simcontainer",

    [string]$InstallRoot = "$env:LOCALAPPDATA\WSL",

    [string]$Asset = "pizza-sim-rootfs.tar.gz",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host ">>> $msg" -ForegroundColor Cyan }

# --- credentials -------------------------------------------------------------
if ($NoEnv) {
    $BasicAuth = ""
}
elseif (-not $BasicAuth) {
    $BasicAuth = Read-Host "Credentials for the .env endpoint (user:password, empty to skip)"
}

if ($BasicAuth -and $BasicAuth -notmatch '^[^:]+:.+$') {
    throw "BasicAuth must be in 'user:password' form."
}
if (-not $BasicAuth) {
    Write-Step "no credentials - the distro will come up with an empty .env"
}

# --- pick a free distro name -------------------------------------------------
$existing = (wsl.exe --list --quiet) -replace "`0", "" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }

if ($existing -contains $Name) {
    if ($Force) {
        Write-Step "removing existing distro '$Name'"
        wsl.exe --unregister $Name | Out-Null
    }
    else {
        $i = 2
        while ($existing -contains "$Name-$i") { $i++ }
        $Name = "$Name-$i"
        Write-Step "name taken, using '$Name' instead"
    }
}

$target = Join-Path $InstallRoot $Name

# --- obtain rootfs -----------------------------------------------------------
if ($Rootfs) {
    if (-not (Test-Path $Rootfs)) { throw "rootfs not found: $Rootfs" }
    $tarball = $Rootfs
    Write-Step "using local rootfs $tarball"
}
else {
    $tarball = Join-Path $env:TEMP $Asset
    if (-not (Test-Path $tarball)) {
        $url = "https://github.com/$Repo/releases/latest/download/$Asset"
        Write-Step "downloading $url"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            Invoke-WebRequest -Uri $url -OutFile $tarball -UseBasicParsing
        }
        catch {
            throw "download failed - has the build workflow published a release yet? ($_)"
        }
    }
    else {
        Write-Step "using cached $tarball  (delete it to force a re-download)"
    }
}

# --- import ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $target | Out-Null
Write-Step "importing as '$Name' into $target"
wsl.exe --import $Name $target $tarball
if ($LASTEXITCODE -ne 0) { throw "wsl --import failed with exit code $LASTEXITCODE" }

# --- bootstrap ---------------------------------------------------------------
Write-Step "bootstrapping"
wsl.exe -d $Name -u root -e env DEVBOX_BASICAUTH="$BasicAuth" `
    /usr/local/bin/devbox-bootstrap

# Restart so /etc/wsl.conf (default user, systemd) takes effect
wsl.exe --terminate $Name | Out-Null

Write-Host ""
Write-Host "Distro '$Name' is ready." -ForegroundColor Green
Write-Host "  enter    : wsl -d $Name"
Write-Host "  fill .env: wsl -d $Name -u root -- devbox-bootstrap user:password"
Write-Host "  discard  : wsl --unregister $Name"
Write-Host ""

wsl.exe -d $Name
