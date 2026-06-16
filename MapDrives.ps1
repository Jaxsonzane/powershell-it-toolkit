# ============================================================
#  MapDrives.ps1 - Network Drive Mapper
#  Run as Administrator in PowerShell
#  Update the drive paths and server names below before use
# ============================================================

# ============================================================
# CONFIGURATION - Update these values for your environment
# ============================================================
$SERVER   = "\\YOUR-FILE-SERVER"        # e.g. \\fileserver or \\192.168.1.100
$DOMAIN   = "YOURDOMAIN"               # e.g. CORP or CONTOSO

# Drive letter -> share path mappings
# Update these to match your network shares
$drives = @{
    "G" = "$SERVER\share1"
    "S" = "$SERVER\share2"
    "W" = "$SERVER\share3"
    "H" = "$SERVER\home"
}

# VPN detection - set to the hostname/IP that resolves only when VPN is up
# Leave blank to skip VPN check
$VPN_CHECK_HOST = ""   # e.g. "fileserver.internal.yourdomain.com"

# ============================================================
# SCRIPT
# ============================================================
$username = $env:USERNAME

Write-Host "`n=== MapDrives - Network Drive Mapper ===" -ForegroundColor Cyan
Write-Host "Run by: $username | $(Get-Date)`n" -ForegroundColor Gray

# Remove all existing drive mappings
Write-Host "Removing existing drive mappings..." -ForegroundColor Yellow
net use * /d /y | Out-Null
Write-Host "   Done." -ForegroundColor Green

# Optional VPN connectivity check
if ($VPN_CHECK_HOST -ne "") {
    Write-Host "`nChecking VPN connectivity..." -ForegroundColor Yellow
    Write-Host "   Waiting for VPN connection to $VPN_CHECK_HOST..." -ForegroundColor Gray

    $timeout = 60   # seconds to wait
    $elapsed = 0
    $connected = $false

    do {
        $resolve = Resolve-DnsName $VPN_CHECK_HOST -ErrorAction SilentlyContinue
        if ($resolve) {
            $connected = $true
        } else {
            Start-Sleep -Seconds 5
            $elapsed += 5
            Write-Host "   Still waiting... ($elapsed/$timeout sec)" -ForegroundColor Gray
        }
    } until ($connected -or $elapsed -ge $timeout)

    if ($connected) {
        Write-Host "   VPN connected!" -ForegroundColor Green
    } else {
        Write-Host "   WARNING: Could not verify VPN connection after ${timeout}s." -ForegroundColor Red
        Write-Host "   Attempting drive mapping anyway..." -ForegroundColor Yellow
    }
} else {
    Write-Host "`nSkipping VPN check (VPN_CHECK_HOST not configured)." -ForegroundColor Gray
}

# Map drives
Write-Host "`nMapping drives..." -ForegroundColor Yellow
$successCount = 0
$failCount    = 0

foreach ($letter in $drives.Keys) {
    $path = $drives[$letter]
    $result = net use "${letter}:" $path /user:$DOMAIN\$username 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ${letter}: -> $path  [OK]" -ForegroundColor Green
        $successCount++
    } else {
        Write-Host "   ${letter}: -> $path  [FAILED] $result" -ForegroundColor Red
        $failCount++
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "   Mapped:  $successCount drive(s)" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "   Failed:  $failCount drive(s)" -ForegroundColor Red
    Write-Host "   Tip: Make sure VPN is connected and the server is reachable." -ForegroundColor Yellow
}

Start-Sleep -Seconds 3
