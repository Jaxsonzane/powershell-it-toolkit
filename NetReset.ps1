# ============================================================
#  NetReset.ps1 - Full Network Stack Reset
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== NetReset - Network Stack Reset ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray
Write-Host "WARNING: This will reset your network stack. You will lose connectivity briefly." -ForegroundColor Red
Write-Host "Type 'confirm' to proceed or 'exit' to cancel." -ForegroundColor Yellow

do {
    $choice = Read-Host "Choice"
} while ($choice -ne "confirm" -and $choice -ne "exit")

if ($choice -eq "exit") {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit
}

# --- 1. Flush DNS ---
Write-Host "`n[1/7] Flushing DNS cache..." -ForegroundColor Yellow
ipconfig /flushdns | Out-Null
Write-Host "     Done." -ForegroundColor Green

# --- 2. Release & Renew DHCP ---
Write-Host "[2/7] Releasing and renewing IP address..." -ForegroundColor Yellow
ipconfig /release | Out-Null
Start-Sleep -Seconds 2
ipconfig /renew | Out-Null
Write-Host "     Done." -ForegroundColor Green

# --- 3. Reset Winsock ---
Write-Host "[3/7] Resetting Winsock..." -ForegroundColor Yellow
netsh winsock reset | Out-Null
Write-Host "     Done." -ForegroundColor Green

# --- 4. Reset TCP/IP Stack ---
Write-Host "[4/7] Resetting TCP/IP stack..." -ForegroundColor Yellow
netsh int ip reset | Out-Null
Write-Host "     Done." -ForegroundColor Green

# --- 5. Reset IPv6 ---
Write-Host "[5/7] Resetting IPv6..." -ForegroundColor Yellow
netsh int ipv6 reset | Out-Null
Write-Host "     Done." -ForegroundColor Green

# --- 6. Clear ARP Cache ---
Write-Host "[6/7] Clearing ARP cache..." -ForegroundColor Yellow
netsh interface ip delete arpcache | Out-Null
Write-Host "     Done." -ForegroundColor Green

# --- 7. Optional NIC Reset ---
Write-Host "[7/7] Reset Network Adapter? This will briefly disconnect you." -ForegroundColor Yellow
Write-Host "     Type 'run' to reset adapter or 'skip' to skip." -ForegroundColor Gray
do {
    $nicChoice = Read-Host "     Choice"
} while ($nicChoice -ne "run" -and $nicChoice -ne "skip")

if ($nicChoice -eq "run") {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    foreach ($a in $adapters) {
        Write-Host "     Resetting adapter: $($a.Name)..." -ForegroundColor Gray
        Disable-NetAdapter -Name $a.Name -Confirm:$false
        Start-Sleep -Seconds 2
        Enable-NetAdapter -Name $a.Name -Confirm:$false
    }
    Write-Host "     Done." -ForegroundColor Green
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
}

# --- Done ---
Write-Host "`n=== Reset Complete. Reboot recommended for full effect. ===" -ForegroundColor Cyan
