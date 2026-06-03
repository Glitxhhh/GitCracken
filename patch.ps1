# GitCracken Patcher — Windows
# Run from the root of this repo: .\patch.ps1
# Or with a specific feature:     .\patch.ps1 -Feature standalone
# Or targeting a specific asar:   .\patch.ps1 -Asar "C:\path\to\app.asar"

param(
    [string]$Feature = "pro",
    [string]$Asar    = ""
)

# Fix UTF-8 so figlet art and unicode display correctly through the pipeline
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding          = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $Root "patch.log"

# Start capturing everything to patch.log
Start-Transcript -Path $LogFile -Force | Out-Null
Write-Host "Logging to: $LogFile"

# ── Helpers ────────────────────────────────────────────────────────────────────
function Info  { param($msg) Write-Host "  --> $msg" -ForegroundColor Cyan }
function Ok    { param($msg) Write-Host "  [ok] $msg" -ForegroundColor Green }
function Err   {
    param($msg)
    Write-Host "  [!!] $msg" -ForegroundColor Red
    Write-Host "`nLog saved to: $LogFile" -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    Read-Host "`nPress Enter to close"
    exit 1
}
function Title { param($msg) Write-Host "`n==> $msg" -ForegroundColor White }

# ── Check Node.js ──────────────────────────────────────────────────────────────
Title "Checking prerequisites"
try {
    $nodeVer = node --version 2>&1
    Ok "Node.js $nodeVer"
} catch {
    Err "Node.js not found. Install from https://nodejs.org (v16 LTS or later)"
}

# ── Pick package manager (yarn preferred, npm fallback) ───────────────────────
$pm = "npm"
try {
    yarn --version 2>&1 | Out-Null
    $pm = "yarn"
    Ok "Package manager: yarn"
} catch {
    Ok "Package manager: npm (yarn not found, that's fine)"
}

# ── Install dependencies ───────────────────────────────────────────────────────
Title "Installing dependencies"
$nmDir = Join-Path $Root "node_modules"
$installedMarker = if ($pm -eq "yarn") {
    Join-Path $nmDir ".yarn-integrity"
} else {
    Join-Path $nmDir ".package-lock.json"
}
$pkgJson     = Join-Path $Root "package.json"
$needsInstall = (-not (Test-Path $installedMarker)) -or
                ((Get-Item $pkgJson).LastWriteTime -gt (Get-Item $installedMarker).LastWriteTime)

if (-not $needsInstall) {
    Ok "Dependencies already up to date (skipping install)"
} else {
    Push-Location $Root
    try {
        if ($pm -eq "yarn") {
            yarn install --frozen-lockfile 2>&1
        } else {
            npm install 2>&1
        }
        if ($LASTEXITCODE -ne 0) { Err "Dependency install failed (exit $LASTEXITCODE)" }
        Ok "Dependencies installed"
    } catch {
        Err "Dependency install failed: $_"
    } finally {
        Pop-Location
    }
}

# ── Build TypeScript ───────────────────────────────────────────────────────────
Title "Building"
$distEntry = Join-Path $Root "dist\bin\gitcracken.js"
$needsBuild = -not (Test-Path $distEntry)
if (-not $needsBuild) {
    $distTime = (Get-Item $distEntry).LastWriteTime
    $staleTs  = Get-ChildItem $Root -Recurse -Include "*.ts" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\node_modules\\' } |
                Where-Object { $_.LastWriteTime -gt $distTime }
    $needsBuild = @($staleTs).Count -gt 0
}

if (-not $needsBuild) {
    Ok "Build already up to date (skipping build)"
} else {
    Push-Location $Root
    try {
        if ($pm -eq "yarn") {
            yarn build 2>&1
        } else {
            npm run build 2>&1
        }
        if ($LASTEXITCODE -ne 0) { Err "Build failed (exit $LASTEXITCODE)" }
        Ok "Build complete"
    } catch {
        Err "Build failed: $_"
    } finally {
        Pop-Location
    }
}

# ── Run patcher ────────────────────────────────────────────────────────────────
Title "Patching GitKraken (feature: $Feature)"

$script = Join-Path $Root "dist\bin\gitcracken.js"
if (-not (Test-Path $script)) {
    Err "Build output not found at $script — did the build step fail?"
}

$patcherArgs  = @("patcher", "-f", $Feature)
$resolvedAsar = $Asar   # will be overwritten by auto-detect branch if needed
if ($Asar -ne "") {
    Info "Using custom asar: $Asar"
    $patcherArgs += @("-a", $Asar)
} else {
    Info "Auto-detecting GitKraken installation..."
    $searchRoots = @(
        "$env:LOCALAPPDATA\gitkraken",
        "C:\ProgramData\$env:USERNAME\gitkraken",
        "$env:LOCALAPPDATA\Programs\gitkraken"
    )
    $detectedAsar = $null
    foreach ($searchRoot in $searchRoots) {
        if (-not (Test-Path $searchRoot)) { continue }
        $latest = Get-ChildItem $searchRoot -Directory -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '^app-\d+\.\d+\.\d+$' } |
                  Sort-Object Name -Descending |
                  Select-Object -First 1
        if ($latest) {
            $candidate = Join-Path $latest.FullName "resources\app.asar"
            if (Test-Path $candidate) {
                $detectedAsar = $candidate
                Info "Found: $detectedAsar"
                break
            }
        }
    }
    if (-not $detectedAsar) {
        Err "Could not find app.asar in any known GitKraken install path. Pass -Asar explicitly."
    }
    $patcherArgs  += @("-a", $detectedAsar)
    $resolvedAsar  = $detectedAsar
}

# ── Check if already patched ───────────────────────────────────────────────────
# The patcher always creates app.asar.<timestamp>.backup before modifying the asar.
# If one exists we know the asar has been patched at least once.
$asarDir = Split-Path $resolvedAsar -Parent
$backups = Get-ChildItem $asarDir -Filter "app.asar.*.backup" -ErrorAction SilentlyContinue
if ($backups) {
    $latestBackup = ($backups | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name
    Info "Existing patch backup found: $latestBackup"
    $resp = Read-Host "  --> GitKraken appears already patched. Re-patch anyway? (y/N)"
    if ($resp -notmatch '^[yY]$') {
        Write-Host "`nSkipping — GitKraken is already patched." -ForegroundColor Yellow
        Write-Host "Log saved to: $LogFile" -ForegroundColor Yellow
        Stop-Transcript | Out-Null
        Read-Host "`nPress Enter to close"
        exit 0
    }
    Info "Re-patching..."
}

try {
    & node $script @patcherArgs 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { Err "Patcher exited with code $LASTEXITCODE" }
} catch {
    Err "Patcher failed: $_"
}

Write-Host ""
Write-Host "Done! Re-launch GitKraken and re-login to apply the license." -ForegroundColor Green
Write-Host "Log saved to: $LogFile" -ForegroundColor Yellow
Stop-Transcript | Out-Null
Read-Host "`nPress Enter to close"
