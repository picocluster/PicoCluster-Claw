#Requires -Version 5.1
# update-windows.ps1 — Update PicoCluster Claw on Windows Solo
# Usage: .\update-windows.ps1 [--force]

param([switch]$Force)

$ErrorActionPreference = "Stop"
$INSTALL_DIR = "$env:USERPROFILE\picocluster-claw"

function Log { param([string]$msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" }
function Wait-Url {
    param([string]$url, [int]$attempts = 20, [int]$delay = 3)
    for ($i = 1; $i -le $attempts; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $url -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            if ($r.StatusCode -lt 500) { return $true }
        } catch {}
        if ($i -eq $attempts) { return $false }
        Start-Sleep $delay
    }
    return $false
}

Push-Location $INSTALL_DIR

$current = & git rev-parse --short HEAD 2>$null
$latest  = (& git ls-remote origin HEAD 2>$null) -replace '\s.*', '' | Select-Object -First 1
$latest  = if ($latest.Length -ge 7) { $latest.Substring(0,7) } else { "unknown" }

Log "Current: $current"
Log "Latest:  $latest"

if ($current -eq $latest -and -not $Force) {
    Log "Already up to date. Use -Force to rebuild anyway."
    Pop-Location
    exit 0
}

Log "Updating..."
& git pull --ff-only 2>&1 | Select-Object -Last 5

Log "Pulling ThreadWeaver image from GHCR..."
& docker compose -f docker-compose.yml -f docker-compose.windows.yml pull threadweaver 2>&1 | Select-Object -Last 5

Log "Rebuilding local containers..."
& docker compose -f docker-compose.yml -f docker-compose.windows.yml build --pull openclaw portal 2>&1 | Select-Object -Last 10

Log "Restarting..."
& docker compose -f docker-compose.yml -f docker-compose.windows.yml up -d threadweaver openclaw portal 2>&1 | Select-Object -Last 10

Log "Waiting for services..."
$ready = Wait-Url "http://127.0.0.1:5173/"
if ($ready) { Log "ThreadWeaver ready" }
else { Log "WARNING: ThreadWeaver did not respond — check docker logs" }

# Update user scripts
if (Test-Path "$INSTALL_DIR\scripts\user-bin\windows") {
    Copy-Item "$INSTALL_DIR\scripts\user-bin\windows\*" "$env:USERPROFILE\bin\" -Force
    Log "User scripts updated"
}

$newVer = & git rev-parse --short HEAD 2>$null
Log ""
Log "=== Update complete ==="
Log "  Version: $newVer"
$twStatus = & docker ps --format "{{.Names}}: {{.Status}}" | Select-String "threadweaver"
Log "  Status:  $twStatus"

Pop-Location
