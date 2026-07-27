<#
.SYNOPSIS
    Creates a ready-to-use BPM Pizza Sim WSL distro in one command.

.DESCRIPTION
    Downloads the prebuilt rootfs from the latest GitHub release, imports it as
    a new WSL distro next to any existing ones, runs the bootstrap (which pulls
    the .env from the protected endpoint) and drops you into a shell.

    Designed to be run straight from the network without installing anything:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/BPMspaceUG/bpm-pizza-simcontainer/main/scripts/create_pizzasim_env.ps1))) user:password

    No #Requires statement here - it is not allowed inside a scriptblock.

.PARAMETER BasicAuth
    Credentials for the .env endpoint in "user:password" form. If omitted, the
    script asks once; press Enter to skip. Use -NoEnv to skip without asking.

.PARAMETER Name
    Distro name. Defaults to "pizza-sim". If it already exists, a numeric
    suffix is appended (pizza-sim-2, pizza-sim-3, ...) unless -Reset is given.

.PARAMETER Reset
    Wipe an existing distro of the same name and rebuild it from a freshly
    downloaded rootfs. Everything inside the old distro is destroyed - use this
    between simulation runs so every participant starts from an identical,
    untouched state. Implies a cache-busting re-download.

.PARAMETER NoEnv
    Skip the .env fetch entirely. The distro comes up with an empty .env.

.PARAMETER Rootfs
    Use a local rootfs tarball instead of downloading the release asset.

.PARAMETER Yes
    Skip the confirmation prompt that -Reset would otherwise show.

.EXAMPLE
    create_pizzasim_env user:password

.EXAMPLE
    create_pizzasim_env user:password -Reset

.EXAMPLE
    create_pizzasim_env user:password -Reset -Yes -Name pizza-sim-training
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$BasicAuth,

    [string]$Name = "pizza-sim",

    [switch]$Reset,

    [switch]$Yes,

    [switch]$NoEnv,

    [string]$Rootfs,

    [string]$Repo = "BPMspaceUG/bpm-pizza-simcontainer",

    [string]$InstallRoot = "$env:LOCALAPPDATA\WSL",

    [string]$Asset = "pizza-sim-rootfs.tar.gz",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host ">>> $msg" -ForegroundColor Cyan }

# --- sanity checks -----------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "PowerShell 5.1 or newer is required."
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe not found. Install WSL first:  wsl --install"
}

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

# --- existing distro ---------------------------------------------------------
$existing = (wsl.exe --list --quiet) -replace "`0", "" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }

if ($existing -contains $Name) {
    if ($Reset -or $Force) {
        if ($Reset -and -not $Yes) {
            Write-Host ""
            Write-Host "This destroys the distro '$Name' and everything in it," -ForegroundColor Yellow
            Write-Host "including any work saved inside. This cannot be undone." -ForegroundColor Yellow
            $answer = Read-Host "Type the distro name to confirm"
            if ($answer -ne $Name) { throw "aborted - name did not match." }
        }
        Write-Step "removing existing distro '$Name'"
        wsl.exe --terminate $Name 2>$null | Out-Null
        wsl.exe --unregister $Name
        if ($LASTEXITCODE -ne 0) { throw "wsl --unregister failed for '$Name'" }

        # the vhdx directory occasionally survives an unregister
        $stale = Join-Path $InstallRoot $Name
        if (Test-Path $stale) { Remove-Item $stale -Recurse -Force -ErrorAction SilentlyContinue }
    }
    else {
        $i = 2
        while ($existing -contains "$Name-$i") { $i++ }
        $Name = "$Name-$i"
        Write-Step "name taken, using '$Name' instead  (use -Reset to wipe it instead)"
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

    # a reset must not reuse a stale image, otherwise "raw state" is whatever
    # was current the last time somebody ran this
    if ($Reset -and (Test-Path $tarball)) {
        Write-Step "discarding cached rootfs"
        Remove-Item $tarball -Force
    }

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
Write-Host "  reset    : rerun this command with -Reset"
Write-Host "  discard  : wsl --unregister $Name"
Write-Host ""

wsl.exe -d $Name
