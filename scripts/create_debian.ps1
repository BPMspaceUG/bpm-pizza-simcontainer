#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a ready-to-use BPM Pizza Sim WSL distro in one command.

.DESCRIPTION
    Downloads the prebuilt rootfs from the latest GitHub release, imports it as
    a new WSL distro next to any existing ones, runs the bootstrap (which pulls
    the .env from the protected endpoint) and drops you into a shell.

.PARAMETER BasicAuth
    Credentials for https://www.aipizzasim.com/getenv in "user:password" form.

.PARAMETER Name
    Distro name. Defaults to "pizza-sim". If it already exists, a numeric
    suffix is appended (pizza-sim-2, pizza-sim-3, ...).

.EXAMPLE
    create_debian myuser:mypassword

.EXAMPLE
    create_debian myuser:mypassword -Name pizza-sim-experiment
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$BasicAuth,

    [string]$Name = "pizza-sim",

    [string]$Repo = "BPMspaceUG/bpm-pizza-simcontainer",

    [string]$InstallRoot = "$env:LOCALAPPDATA\WSL",

    [string]$Asset = "pizza-sim-rootfs.tar.gz",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host ">>> $msg" -ForegroundColor Cyan }

if ($BasicAuth -notmatch '^[^:]+:.+$') {
    throw "BasicAuth must be in 'user:password' form."
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
$tarball = Join-Path $env:TEMP $Asset

# --- download rootfs ---------------------------------------------------------
if (-not (Test-Path $tarball)) {
    $url = "https://github.com/$Repo/releases/latest/download/$Asset"
    Write-Step "downloading $url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tarball -UseBasicParsing
}
else {
    Write-Step "using cached $tarball  (delete it to force a re-download)"
}

# --- import ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $target | Out-Null
Write-Step "importing as '$Name' into $target"
wsl.exe --import $Name $target $tarball
if ($LASTEXITCODE -ne 0) { throw "wsl --import failed with exit code $LASTEXITCODE" }

# --- bootstrap ---------------------------------------------------------------
Write-Step "bootstrapping (fetching .env)"
wsl.exe -d $Name -u root -- /usr/local/bin/devbox-bootstrap $BasicAuth
if ($LASTEXITCODE -ne 0) {
    Write-Warning "bootstrap failed. The distro exists; fix credentials and rerun:"
    Write-Warning "  wsl -d $Name -u root -- devbox-bootstrap user:password"
    exit 1
}

# Restart so /etc/wsl.conf (default user, systemd) takes effect
wsl.exe --terminate $Name | Out-Null

Write-Host ""
Write-Host "Distro '$Name' is ready." -ForegroundColor Green
Write-Host "  enter    : wsl -d $Name"
Write-Host "  discard  : wsl --unregister $Name"
Write-Host ""

wsl.exe -d $Name
