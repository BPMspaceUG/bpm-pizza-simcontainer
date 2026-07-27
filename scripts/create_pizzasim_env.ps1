<#
.SYNOPSIS
    Creates a ready-to-use BPM Pizza Sim WSL distro in one command.

.DESCRIPTION
    Downloads the prebuilt rootfs from the latest GitHub release, imports it as
    a new WSL distro next to any existing ones, runs the bootstrap (which pulls
    the .env) and drops you into a shell.

    Designed to be run straight from the network without installing anything:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/BPMspaceUG/bpm-pizza-simcontainer/main/scripts/create_pizzasim_env.ps1))) user:password

    No #Requires statement here - it is not allowed inside a scriptblock.

.PARAMETER BasicAuth
    Credentials for the .env endpoint in "user:password" form. Only needed if
    the endpoint is protected. If neither this nor -EnvUrl / -EnvFile / -NoEnv
    is given, the script asks once; press Enter to skip.

.PARAMETER EnvUrl
    Full URL to fetch the .env from, including the filename if the host serves
    static files. Replaces the default endpoint
    (https://www.aipizzasim.com/getenv). Works with or without -BasicAuth.

.PARAMETER EnvFile
    Full path to a local .env on the Windows side, including the filename. Its
    contents are piped into the distro; no network request is made.

.PARAMETER Name
    Distro name. Defaults to "pizza-sim". If it already exists, a numeric
    suffix is appended (pizza-sim-2, pizza-sim-3, ...).

.PARAMETER SetDefault
    Make this distro the WSL default, so a bare "wsl" starts it. Handy on a
    training machine; leave it off to keep an existing distro as the default.

.PARAMETER NoEnv
    Skip the .env entirely. The distro comes up with an empty .env.

.PARAMETER Rootfs
    Use a local rootfs tarball instead of downloading the release asset.

.PARAMETER FreshDownload
    Ignore and delete any cached rootfs before downloading.

.EXAMPLE
    create_pizzasim_env user:password -SetDefault

.EXAMPLE
    create_pizzasim_env -EnvUrl https://example.com/path/pizza.env -SetDefault

.EXAMPLE
    create_pizzasim_env -EnvFile C:\sim\pizza.env

.EXAMPLE
    create_pizzasim_env -NoEnv -Name pizza-sim-test
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$BasicAuth,

    [string]$EnvUrl,

    [string]$EnvFile,

    [string]$Name = "pizza-sim",

    [switch]$SetDefault,

    [switch]$NoEnv,

    [string]$Rootfs,

    [switch]$FreshDownload,

    [string]$Repo = "BPMspaceUG/bpm-pizza-simcontainer",

    [string]$InstallRoot = "$env:LOCALAPPDATA\WSL",

    [string]$Asset = "pizza-sim-rootfs.tar.gz",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host ">>> $msg" -ForegroundColor Cyan }

function Get-RemoteSize($url) {
    try {
        $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing
        $len = $r.Headers['Content-Length']
        if ($len) { return [int64]($len | Select-Object -First 1) }
    }
    catch { }
    return $null
}

# --- sanity checks -----------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "PowerShell 5.1 or newer is required."
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe not found. Install WSL first:  wsl --install"
}
if ($EnvFile -and -not (Test-Path $EnvFile)) {
    throw "EnvFile not found: $EnvFile"
}

# --- where does the .env come from? ------------------------------------------
# Precedence matches devbox-bootstrap: file, then url, then default endpoint.
$envMode = "none"

if ($NoEnv) {
    $BasicAuth = ""
    $EnvUrl = ""
}
elseif ($EnvFile) {
    $envMode = "file"
    Write-Step "using local .env from $EnvFile"
}
elseif ($EnvUrl) {
    # An explicit URL is enough on its own - credentials are optional.
    $envMode = "url"
    Write-Step "fetching .env from $EnvUrl"
}
else {
    if (-not $BasicAuth) {
        $BasicAuth = Read-Host "Credentials for the .env endpoint (user:password, empty to skip)"
    }
    if ($BasicAuth) {
        $envMode = "url"
        Write-Step "fetching .env from the default endpoint"
    }
}

if ($BasicAuth -and $BasicAuth -notmatch '^[^:]+:.+$') {
    throw "BasicAuth must be in 'user:password' form."
}
if ($envMode -eq "none") {
    Write-Step "no .env source - the distro will come up with an empty .env"
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
# The rootfs is well over a gigabyte. Invoke-WebRequest on Windows PowerShell
# 5.1 truncates files that size often enough to matter, and a truncated tarball
# fails deep inside the import with a confusing bsdtar error. So: prefer
# curl.exe (built into Windows 10+, resumable), then verify the size.
if ($Rootfs) {
    if (-not (Test-Path $Rootfs)) { throw "rootfs not found: $Rootfs" }
    $tarball = $Rootfs
    Write-Step "using local rootfs $tarball"
}
else {
    $tarball = Join-Path $env:TEMP $Asset
    $url = "https://github.com/$Repo/releases/latest/download/$Asset"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $expected = Get-RemoteSize $url

    if ($FreshDownload -and (Test-Path $tarball)) {
        Write-Step "discarding cached rootfs"
        Remove-Item $tarball -Force
    }

    # A cached file only counts if it is complete.
    if ((Test-Path $tarball) -and $expected -and
        ((Get-Item $tarball).Length -ne $expected)) {
        Write-Step "cached rootfs is incomplete or outdated - discarding"
        Remove-Item $tarball -Force
    }

    if (Test-Path $tarball) {
        Write-Step "using cached $tarball"
    }
    else {
        if ($expected) {
            Write-Step ("downloading {0:N0} MB from {1}" -f ($expected / 1MB), $url)
        }
        else {
            Write-Step "downloading $url"
        }

        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
            & $curl.Source -L --fail --retry 3 --retry-delay 2 -C - `
                -o $tarball $url
            $ok = ($LASTEXITCODE -eq 0)
        }
        else {
            try {
                Invoke-WebRequest -Uri $url -OutFile $tarball -UseBasicParsing
                $ok = $true
            }
            catch {
                Write-Warning $_
                $ok = $false
            }
        }

        if (-not $ok) {
            Remove-Item $tarball -Force -ErrorAction SilentlyContinue
            throw "download failed. Has the build workflow published a release yet?"
        }

        $got = (Get-Item $tarball).Length
        if ($expected -and $got -ne $expected) {
            Remove-Item $tarball -Force -ErrorAction SilentlyContinue
            throw ("download incomplete: got {0:N0} of {1:N0} bytes. Rerun the command." -f $got, $expected)
        }
        Write-Step ("downloaded {0:N0} MB" -f ($got / 1MB))
    }
}

# --- import ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $target | Out-Null
Write-Step "importing as '$Name' into $target"
wsl.exe --import $Name $target $tarball
if ($LASTEXITCODE -ne 0) {
    Write-Warning "If the error mentions a truncated archive, the download is corrupt."
    Write-Warning "Rerun with -FreshDownload to fetch it again."
    throw "wsl --import failed with exit code $LASTEXITCODE"
}

# --- bootstrap ---------------------------------------------------------------
Write-Step "bootstrapping"
if ($envMode -eq "file") {
    Get-Content -Raw -LiteralPath $EnvFile |
        wsl.exe -d $Name -u root -e /usr/local/bin/devbox-bootstrap --stdin
}
else {
    wsl.exe -d $Name -u root -e env `
        DEVBOX_BASICAUTH="$BasicAuth" `
        DEVBOX_ENV_URL="$EnvUrl" `
        /usr/local/bin/devbox-bootstrap
}

# Restart so /etc/wsl.conf (default user, systemd) takes effect
wsl.exe --terminate $Name | Out-Null

# --- default distro ----------------------------------------------------------
if ($SetDefault) {
    wsl.exe --set-default $Name
    if ($LASTEXITCODE -eq 0) {
        Write-Step "'$Name' is now the WSL default - a bare 'wsl' starts it"
    }
    else {
        Write-Warning "could not set '$Name' as default; use: wsl --set-default $Name"
    }
}

Write-Host ""
Write-Host "Distro '$Name' is ready." -ForegroundColor Green
if ($SetDefault) {
    Write-Host "  enter    : wsl"
}
else {
    Write-Host "  enter    : wsl -d $Name"
    Write-Host "  default  : wsl --set-default $Name"
}
Write-Host "  fill .env: wsl -d $Name -u root -- devbox-bootstrap user:password"
Write-Host "  discard  : wsl --unregister $Name"
Write-Host ""

wsl.exe -d $Name
