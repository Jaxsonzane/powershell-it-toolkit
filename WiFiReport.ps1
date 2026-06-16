# ============================================================
#  WiFiReport.ps1 - Wi-Fi Health Check
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== WiFiReport - Wi-Fi Health Check ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

# --- 1. Check for Wi-Fi Adapter ---
# Match on both Name and InterfaceDescription to catch Intel/Realtek adapters
Write-Host "[1/5] Checking Wi-Fi adapter..." -ForegroundColor Yellow
$wifiAdapter = Get-NetAdapter | Where-Object {
    ($_.Name -match "Wi-Fi|Wireless|WLAN" -or $_.InterfaceDescription -match "Wi-Fi|Wireless|802\.11|WLAN") -and $_.Status -eq "Up"
}
if ($wifiAdapter) {
    Write-Host "     Adapter:     $($wifiAdapter.Name)" -ForegroundColor Green
    Write-Host "     Description: $($wifiAdapter.InterfaceDescription)" -ForegroundColor Green
    Write-Host "     Status:      $($wifiAdapter.Status) | Speed: $($wifiAdapter.LinkSpeed)" -ForegroundColor Green
} else {
    # Still show all adapters so user can see what's present
    Write-Host "     WARNING: No active Wi-Fi adapter found. Are you on ethernet?" -ForegroundColor Red
    Write-Host "     All detected adapters:" -ForegroundColor Gray
    Get-NetAdapter | ForEach-Object {
        Write-Host "       - $($_.Name) | $($_.InterfaceDescription) | $($_.Status)" -ForegroundColor Gray
    }
}

# --- 2. Current SSID & Signal Strength ---
Write-Host "`n[2/5] Current Wi-Fi connection..." -ForegroundColor Yellow
$wlanOutput = netsh wlan show interfaces
$ssid      = ($wlanOutput | Select-String "SSID\s+:" | Where-Object { $_ -notmatch "BSSID" } | Select-Object -First 1) -replace ".*:\s+", ""
$signal    = ($wlanOutput | Select-String "Signal") -replace ".*:\s+", ""
$channel   = ($wlanOutput | Select-String "Channel") -replace ".*:\s+", ""
$radioType = ($wlanOutput | Select-String "Radio type") -replace ".*:\s+", ""
$band      = ($wlanOutput | Select-String "Band") -replace ".*:\s+", ""

if ($ssid) {
    Write-Host "     SSID:       $ssid" -ForegroundColor Green
    Write-Host "     Signal:     $signal" -ForegroundColor $(if ($signal -match "^[0-9]+" -and [int]($signal -replace "%","") -lt 50) { "Red" } else { "Green" })
    Write-Host "     Channel:    $channel" -ForegroundColor Gray
    Write-Host "     Radio Type: $radioType" -ForegroundColor Gray
    Write-Host "     Band:       $band" -ForegroundColor Gray
} else {
    Write-Host "     Not connected to any Wi-Fi network." -ForegroundColor Red
}

# --- 3. Saved Network Profiles ---
Write-Host "`n[3/5] Saved Wi-Fi profiles on this machine..." -ForegroundColor Yellow
$profiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { ($_ -replace ".*:\s+", "").Trim() }
if ($profiles) {
    $profiles | ForEach-Object { Write-Host "     - $_" -ForegroundColor Gray }
} else {
    Write-Host "     No saved profiles found." -ForegroundColor Gray
}

# --- 4. Driver Info ---
# Use InterfaceDescription match to find Intel/Realtek Wi-Fi adapters
Write-Host "`n[4/5] Wi-Fi driver info..." -ForegroundColor Yellow
$driverInfo = Get-WmiObject Win32_NetworkAdapter | Where-Object {
    $_.Name -match "Wi-Fi|Wireless|802\.11|WLAN|Intel.*Wi" -or $_.AdapterType -match "Ethernet 802.3"
} | Select-Object -First 1 Name, DriverVersion
if ($driverInfo) {
    Write-Host "     $($driverInfo.Name)" -ForegroundColor Green
    Write-Host "     Driver Version: $($driverInfo.DriverVersion)" -ForegroundColor Gray
} else {
    Write-Host "     Could not retrieve driver info." -ForegroundColor Gray
}

# --- 5. Generate Windows Wireless Report ---
Write-Host "`n[5/5] Generate full Windows wireless diagnostics report?" -ForegroundColor Yellow
Write-Host "     Type 'run' to generate or 'skip' to skip." -ForegroundColor Gray
do {
    $choice = Read-Host "     Choice"
} while ($choice -ne "run" -and $choice -ne "skip")

if ($choice -eq "run") {
    # Resolve Desktop path safely — handles OneDrive redirection
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    if (-not $desktopPath -or -not (Test-Path $desktopPath)) {
        $desktopPath = "$env:USERPROFILE\Desktop"
    }
    if (-not (Test-Path $desktopPath)) {
        New-Item -ItemType Directory -Path $desktopPath -Force | Out-Null
    }
    $reportPath      = "$desktopPath\WirelessReport.html"
    $generatedReport = "C:\ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html"

    Write-Host "     Generating report..." -ForegroundColor Gray
    netsh wlan show wlanreport | Out-Null
    Start-Sleep -Seconds 2

    if (Test-Path $generatedReport) {
        Copy-Item $generatedReport $reportPath -Force
        Write-Host "     Report saved to: $reportPath" -ForegroundColor Green
        Write-Host "     Open it in a browser for full details." -ForegroundColor Gray
    } else {
        Write-Host "     Report not found at expected path: $generatedReport" -ForegroundColor Red
        Write-Host "     Try running manually: netsh wlan show wlanreport" -ForegroundColor Yellow
    }
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
}

Write-Host "`n=== Wi-Fi Check Complete ===" -ForegroundColor Cyan
