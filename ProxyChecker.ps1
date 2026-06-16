# ============================================================
#  ProxyChecker.ps1 - Proxy & DNS Audit
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== ProxyChecker - Proxy & DNS Audit ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

# --- 1. Check Proxy Settings ---
Write-Host "[1/5] Checking proxy settings..." -ForegroundColor Yellow
$proxyReg = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
$proxyEnabled = $proxyReg.ProxyEnable
$proxyServer  = $proxyReg.ProxyServer
$autoConfig   = $proxyReg.AutoConfigURL

if ($proxyEnabled -eq 1) {
    Write-Host "     WARNING: Manual proxy is ENABLED -> $proxyServer" -ForegroundColor Red
    Write-Host "     This may be causing connectivity issues. Disable it in Settings > Proxy if unintended." -ForegroundColor Yellow
} else {
    Write-Host "     Manual proxy: Disabled (normal)" -ForegroundColor Green
}

if ($autoConfig) {
    Write-Host "     Auto-config URL (PAC): $autoConfig" -ForegroundColor Yellow
} else {
    Write-Host "     Auto-config (PAC): None" -ForegroundColor Green
}

# Check WinHTTP system proxy (affects apps like Windows Update)
Write-Host "`n     WinHTTP system proxy:" -ForegroundColor Gray
netsh winhttp show proxy

# --- 2. Check Current DNS Servers ---
Write-Host "`n[2/5] Current DNS servers..." -ForegroundColor Yellow
$dnsServers = Get-DnsClientServerAddress | Where-Object { $_.AddressFamily -eq 2 -and $_.ServerAddresses }
foreach ($d in $dnsServers) {
    Write-Host "     Interface: $($d.InterfaceAlias) | DNS: $($d.ServerAddresses -join ', ')" -ForegroundColor Gray
}

# --- 3. DNS Resolution Tests ---
Write-Host "`n[3/5] Testing DNS resolution..." -ForegroundColor Yellow
$testHosts = @("google.com", "microsoft.com", "github.com", "cloudflare.com")
$allResolved = $true
foreach ($h in $testHosts) {
    try {
        $ip = [System.Net.Dns]::GetHostAddresses($h) | Select-Object -First 1
        Write-Host "     $h -> $($ip.IPAddressToString)" -ForegroundColor Green
    } catch {
        Write-Host "     FAILED: $h could not be resolved" -ForegroundColor Red
        $allResolved = $false
    }
}

if (-not $allResolved) {
    Write-Host "`n     TIP: DNS resolution failing. Try setting DNS to 8.8.8.8 / 1.1.1.1 manually." -ForegroundColor Yellow
}

# --- 4. Test HTTP Connectivity ---
Write-Host "`n[4/5] HTTP connectivity test..." -ForegroundColor Yellow
$testUrls = @(
    "https://www.google.com",
    "https://www.microsoft.com",
    "https://1.1.1.1"
)
foreach ($url in $testUrls) {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
        Write-Host "     $url -> HTTP $($r.StatusCode) OK" -ForegroundColor Green
    } catch {
        Write-Host "     FAILED: $url -> $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- 5. Optional: Clear Bad Proxy Settings ---
Write-Host "`n[5/5] Clear proxy settings?" -ForegroundColor Yellow
Write-Host "     This will disable any manual proxy and clear the PAC URL." -ForegroundColor Gray
Write-Host "     Type 'run' to clear or 'skip' to skip." -ForegroundColor Gray
do {
    $choice = Read-Host "     Choice"
} while ($choice -ne "run" -and $choice -ne "skip")

if ($choice -eq "run") {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 0
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name AutoConfigURL -ErrorAction SilentlyContinue
    Write-Host "     Proxy settings cleared." -ForegroundColor Green
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
}

Write-Host "`n=== Proxy & DNS Audit Complete ===" -ForegroundColor Cyan
