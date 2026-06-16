# ============================================================
#  NetMonitor.ps1 - Live Connection Monitor
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== NetMonitor - Live Connection Monitor ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

# Resolve Desktop path safely — handles OneDrive redirection
$desktopPath = [Environment]::GetFolderPath("Desktop")
if (-not $desktopPath -or -not (Test-Path $desktopPath)) {
    $desktopPath = "$env:USERPROFILE\Desktop"
}
if (-not (Test-Path $desktopPath)) {
    New-Item -ItemType Directory -Path $desktopPath -Force | Out-Null
}
$logPath = "$desktopPath\NetMonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$logLines = @()
$recommendations = @()

function Log($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
    $script:logLines += $msg
}

# --- 1. Active TCP Connections ---
Log "[1/4] Active TCP Connections..." "Yellow"
Log ("     {0,-30} {1,-25} {2,-15} {3}" -f "Process", "Remote Address", "Remote Port", "State") "Gray"
Log ("     " + ("-" * 85)) "Gray"

$suspiciousFound = $false
$connections = Get-NetTCPConnection | Where-Object { $_.State -eq "Established" } | Sort-Object OwningProcess

foreach ($conn in $connections) {
    try {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        $procName = if ($proc) { $proc.Name } else { "Unknown (PID $($conn.OwningProcess))" }
        $remote = $conn.RemoteAddress
        $port   = $conn.RemotePort

        $flag = ""
        if ($port -in @(4444, 5555, 6666, 7777, 8888, 9999, 31337)) {
            $flag = " <-- SUSPICIOUS PORT"
            $suspiciousFound = $true
            $script:recommendations += "SECURITY: Suspicious port $port detected on process '$procName' connecting to $remote. Investigate immediately — run a malware scan and review the process in Task Manager."
        }

        $color = if ($flag) { "Red" } else { "White" }
        Log ("     {0,-30} {1,-25} {2,-15} {3}{4}" -f $procName, $remote, $port, $conn.State, $flag) $color
    } catch {
        Log "     Could not retrieve process for PID $($conn.OwningProcess)" "Gray"
    }
}

if (-not $suspiciousFound) {
    $script:recommendations += "CONNECTIONS: No suspicious ports detected. Active connections look normal."
}

# --- 2. Listening Ports ---
Log "`n[2/4] Listening Ports (potential exposure)..." "Yellow"
$listening = Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Sort-Object LocalPort
Log ("     {0,-10} {1,-30} {2}" -f "Port", "Process", "Local Address") "Gray"
Log ("     " + ("-" * 60)) "Gray"

$exposedPorts = @()
foreach ($l in $listening) {
    try {
        $proc = Get-Process -Id $l.OwningProcess -ErrorAction SilentlyContinue
        $procName = if ($proc) { $proc.Name } else { "Unknown (PID $($l.OwningProcess))" }
        Log ("     {0,-10} {1,-30} {2}" -f $l.LocalPort, $procName, $l.LocalAddress) "Gray"
        if ($l.LocalAddress -eq "0.0.0.0") {
            $exposedPorts += "$($l.LocalPort) ($procName)"
        }
    } catch {}
}

if ($exposedPorts.Count -gt 0) {
    $script:recommendations += "LISTENING PORTS: The following ports are listening on all interfaces (0.0.0.0) and may be exposed: $($exposedPorts -join ', '). Review these in Windows Firewall and close any that aren't needed."
} else {
    $script:recommendations += "LISTENING PORTS: No ports found listening on all interfaces. Looks good."
}

# --- 3. High Bandwidth Processes (Network I/O snapshot) ---
Log "`n[3/4] Top processes by network activity (5 sec sample)..." "Yellow"
Write-Host "     Sampling for 5 seconds..." -ForegroundColor Gray

$before = Get-NetAdapterStatistics
Start-Sleep -Seconds 5
$after  = Get-NetAdapterStatistics

$totalSentKB     = [math]::Round(($after | Measure-Object SentBytes -Sum).Sum / 1KB - ($before | Measure-Object SentBytes -Sum).Sum / 1KB, 1)
$totalReceivedKB = [math]::Round(($after | Measure-Object ReceivedBytes -Sum).Sum / 1KB - ($before | Measure-Object ReceivedBytes -Sum).Sum / 1KB, 1)

Log "     Total Sent (5s):     ${totalSentKB} KB" "Green"
Log "     Total Received (5s): ${totalReceivedKB} KB" "Green"

if ($totalReceivedKB -gt 5000 -or $totalSentKB -gt 5000) {
    Log "     WARNING: High network usage detected. Check processes below." "Red"
    $script:recommendations += "BANDWIDTH: High network activity detected (Sent: ${totalSentKB} KB, Received: ${totalReceivedKB} KB in 5 seconds). Check Task Manager > Performance > Open Resource Monitor > Network tab to identify the process consuming bandwidth. Common culprits: Windows Update, OneDrive sync, antivirus, or backup software."
} else {
    $script:recommendations += "BANDWIDTH: Network usage looks normal (Sent: ${totalSentKB} KB, Received: ${totalReceivedKB} KB in 5 seconds)."
}

Log "`n     Top 5 active processes (RAM proxy for activity):" "Gray"
$topProcs = Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5
foreach ($p in $topProcs) {
    Log ("     {0,-30} RAM: {1} MB" -f $p.Name, [math]::Round($p.WorkingSet/1MB, 1)) "Gray"
}

$highRamProc = $topProcs | Where-Object { ($_.WorkingSet/1MB) -gt 500 }
if ($highRamProc) {
    foreach ($p in $highRamProc) {
        $script:recommendations += "HIGH RAM: Process '$($p.Name)' is using $([math]::Round($p.WorkingSet/1MB, 1)) MB of RAM. If the machine is slow, consider restarting this process or rebooting."
    }
}

# --- 4. DNS Cache Snapshot ---
Log "`n[4/4] DNS Cache (top 20 entries)..." "Yellow"
$dnsCache = Get-DnsClientCache | Select-Object -First 20
if ($dnsCache) {
    $dnsCache | ForEach-Object {
        Log ("     {0,-40} -> {1}" -f $_.Entry, $_.Data) "Gray"
    }
    $script:recommendations += "DNS CACHE: Cache is populated and working. If a user reports a specific site not loading, run 'ipconfig /flushdns' to clear stale entries and retry."
} else {
    Log "     DNS cache is empty." "Gray"
    $script:recommendations += "DNS CACHE: Cache is empty. This is normal after a flush or reboot. No action needed."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $script:recommendations) {
    $color = if ($rec -match "WARNING|SUSPICIOUS|HIGH RAM|SECURITY|BANDWIDTH.*High") { "Red" } elseif ($rec -match "Looks good|normal|working") { "Green" } else { "Yellow" }
    Write-Host "  $i. $rec" -ForegroundColor $color
    $i++
}

# --- Save Log ---
Log "`n=== NetMonitor Complete ===" "Cyan"
$script:logLines += "`n=== Recommended Actions ==="
$i = 1
foreach ($rec in $script:recommendations) {
    $script:logLines += "  $i. $rec"
    $i++
}
$script:logLines | Out-File -FilePath $logPath -Encoding UTF8
Write-Host "`nLog saved to: $logPath" -ForegroundColor Cyan
