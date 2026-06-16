# ============================================================
#  MorningStartup.ps1 - Daily Morning Reset & Health Check
#  Run as Administrator in PowerShell
# ============================================================

$startTime = Get-Date
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   Morning Startup - $(Get-Date -Format 'dddd, MMMM dd yyyy')" -ForegroundColor Cyan
Write-Host "   $env:USERNAME @ $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "=============================================`n" -ForegroundColor Cyan

$warnings = @()
$issues   = @()
$summary  = @()

function Step($msg) { Write-Host ">> $msg" -ForegroundColor Yellow }
function OK($msg)   { Write-Host "   OK: $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "   WARN: $msg" -ForegroundColor Yellow; $script:warnings += $msg }
function Fail($msg) { Write-Host "   ISSUE: $msg" -ForegroundColor Red; $script:issues += $msg }
function Info($msg) { Write-Host "   $msg" -ForegroundColor Gray }

# ============================================================
# 1. CLEAR TEMP FILES
# ============================================================
Step "Clearing temp files..."
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
OK "Temp files cleared."

# ============================================================
# 2. FLUSH DNS & RESET NETWORK STACK
# ============================================================
Step "Flushing DNS and resetting network stack..."
ipconfig /flushdns | Out-Null
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
OK "DNS flushed. Winsock and TCP/IP reset."

# ============================================================
# 3. SET POWER PLAN TO HIGH PERFORMANCE
# ============================================================
Step "Setting power plan to High Performance..."
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
OK "Power plan set to High Performance."

# ============================================================
# 4. DISK SPACE CHECK
# ============================================================
Step "Checking disk space..."
$disk    = Get-PSDrive C
$freeGB  = [math]::Round($disk.Free / 1GB, 1)
$usedGB  = [math]::Round($disk.Used / 1GB, 1)
$totalGB = [math]::Round(($disk.Used + $disk.Free) / 1GB, 1)
$freePct = [math]::Round(($freeGB / $totalGB) * 100, 0)
$summary += "DISK: ${freeGB} GB free of ${totalGB} GB (${freePct}% free)"

if ($freeGB -lt 10) {
    Fail "Critically low disk space - ${freeGB} GB free. Run diskcleanup immediately."
} elseif ($freeGB -lt 20) {
    Warn "Disk space getting low - ${freeGB} GB free. Consider running diskcleanup."
} else {
    OK "Disk space OK - ${freeGB} GB free."
}

# ============================================================
# 5. MEMORY CHECK & KILL HUNG PROCESSES
# ============================================================
Step "Checking memory and cleaning up hung processes..."
$totalRAMGB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$freeRAMMB  = [math]::Round((Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory / 1KB, 0)
$freeRAMGB  = [math]::Round($freeRAMMB / 1024, 1)
$usedRAMPct = [math]::Round((($totalRAMGB - $freeRAMGB) / $totalRAMGB) * 100, 0)
$summary   += "RAM: ${freeRAMGB} GB free of ${totalRAMGB} GB (${usedRAMPct}% used)"

if ($usedRAMPct -gt 90) {
    Fail "RAM usage critical - ${usedRAMPct}% used. Consider rebooting."
} elseif ($usedRAMPct -gt 75) {
    Warn "RAM usage high - ${usedRAMPct}% used."
} else {
    OK "RAM usage OK - ${usedRAMPct}% used."
}

$hungProcs = @("Teams", "OUTLOOK", "chrome", "msedge", "slack")
$killed    = @()
foreach ($proc in $hungProcs) {
    $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($running) {
        $highMemProcs = $running | Where-Object { $_.WorkingSet/1MB -gt 800 }
        if ($highMemProcs) {
            foreach ($p in $highMemProcs) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                $killed += "$proc ($([math]::Round($p.WorkingSet/1MB,0)) MB)"
            }
        }
    }
}
if ($killed.Count -gt 0) {
    Warn "Killed high-memory overnight processes: $($killed -join ', '). These will reopen when you launch them."
} else {
    OK "No hung overnight processes found."
}

# ============================================================
# 6. SYNC TIME WITH NTP
# ============================================================
Step "Syncing system clock with NTP..."
try {
    w32tm /resync /force 2>$null | Out-Null
    $currentTime = Get-Date
    OK "Clock synced - current time: $($currentTime.ToString('hh:mm tt'))"
    $summary += "TIME: Synced - $($currentTime.ToString('hh:mm tt'))"
} catch {
    Warn "Could not sync clock. Run 'w32tm /resync /force' manually if you get auth issues."
}

# ============================================================
# 7. GROUP POLICY UPDATE
# ============================================================
Step "Running Group Policy update..."
$gpResult = gpupdate /force 2>&1
if ($gpResult -match "successfully") {
    OK "Group Policy updated successfully."
} else {
    Warn "Group Policy update may not have completed. Run 'gpupdate /force' manually if needed."
}

# ============================================================
# 8. NETWORK ADAPTERS CHECK
# ============================================================
Step "Checking network adapters..."
$activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
if ($activeAdapters) {
    foreach ($a in $activeAdapters) {
        $ip = Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch "^169|^127" }
        Info "$($a.Name) - $($a.InterfaceDescription) | IP: $(if ($ip) { $ip.IPAddress } else { 'No IP' })"
    }
    OK "$($activeAdapters.Count) adapter(s) active."
    $summary += "NETWORK: $($activeAdapters.Count) adapter(s) up - $($activeAdapters.Name -join ', ')"
} else {
    Fail "No active network adapters found. Check your ethernet/Wi-Fi connection."
    $summary += "NETWORK: No active adapters"
}

$defaultRoutes = Get-NetRoute | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }
if ($defaultRoutes.Count -gt 1) {
    Warn "$($defaultRoutes.Count) default routes detected. Disable Wi-Fi if on ethernet to avoid VPN conflicts."
}

# ============================================================
# 9. VPN STATUS & CISCO SERVICE CHECK
# ============================================================
Step "Checking VPN and Cisco Secure Client..."
$vpnProfile = "YOUR_VPN_PROFILE_NAME"   # Update to match your VPN profile name

$vpncliPath = $null
$cscSearchPaths = @(
    "$env:ProgramFiles\Cisco\Cisco Secure Client",
    "$env:ProgramFiles(x86)\Cisco\Cisco Secure Client",
    "$env:ProgramFiles\Cisco\Cisco AnyConnect Secure Mobility Client",
    "$env:ProgramFiles(x86)\Cisco\Cisco AnyConnect Secure Mobility Client"
)
foreach ($p in $cscSearchPaths) {
    $candidate = Join-Path $p "vpncli.exe"
    if (Test-Path $candidate) { $vpncliPath = $candidate; break }
}
if (-not $vpncliPath) {
    foreach ($sp in @("$env:ProgramFiles\Cisco", "$env:ProgramFiles(x86)\Cisco")) {
        if (Test-Path $sp) {
            $found = Get-ChildItem $sp -Recurse -Filter "vpncli.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $vpncliPath = $found.FullName; break }
        }
    }
}

$ciscoSvcs  = @("vpnagent", "csc_umbrellaagent", "aciseposture", "csscan")
$svcFailed  = @()
foreach ($svc in $ciscoSvcs) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        if ($s.Status -ne "Running") {
            Start-Service -Name $svc -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $s.Refresh()
        }
        if ($s.Status -ne "Running") { $svcFailed += $svc }
    }
}
if ($svcFailed.Count -gt 0) {
    Fail "Cisco services failed to start: $($svcFailed -join ', '). Run vpnrepair."
} else {
    OK "All Cisco Secure Client services running."
}

if ($vpncliPath) {
    $vpnState = & $vpncliPath state 2>$null
    if ($vpnState -match "Connected") {
        OK "VPN connected to $vpnProfile."
        $summary += "VPN: Connected to $vpnProfile"
    } else {
        Warn "VPN not connected. Open Cisco Secure Client and connect to '$vpnProfile'."
        $summary += "VPN: NOT CONNECTED - open Cisco Secure Client"
    }
} else {
    Warn "vpncli.exe not found - cannot check VPN state. Run vpnrepair."
    $summary += "VPN: Status unknown"
}

# ============================================================
# 10. CLEAR TEAMS CACHE
# ============================================================
Step "Clearing Microsoft Teams cache..."
$teamsCachePaths = @(
    "$env:APPDATA\Microsoft\Teams\Cache",
    "$env:APPDATA\Microsoft\Teams\blob_storage",
    "$env:APPDATA\Microsoft\Teams\GPUCache",
    "$env:APPDATA\Microsoft\Teams\IndexedDB",
    "$env:APPDATA\Microsoft\Teams\Local Storage",
    "$env:APPDATA\Microsoft\Teams\tmp"
)
$teamsFreed = 0
foreach ($path in $teamsCachePaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue
        $size  = if ($files -and $files.Count -gt 0) { [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1) } else { 0 }
        Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
        $teamsFreed += $size
    }
}
OK "Teams cache cleared (~${teamsFreed} MB)."

# ============================================================
# 11. CLEAR BROWSER CACHE
# ============================================================
Step "Clearing browser cache..."
$browserCachePaths = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
)
$browserFreed = 0
foreach ($path in $browserCachePaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue
        $size  = if ($files -and $files.Count -gt 0) { [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1) } else { 0 }
        Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
        $browserFreed += $size
    }
}
OK "Browser cache cleared (~${browserFreed} MB)."

# ============================================================
# 12. CLEAR SLACK CACHE
# ============================================================
Step "Clearing Slack cache..."
$slackCachePaths = @(
    "$env:APPDATA\Slack\Cache",
    "$env:APPDATA\Slack\Code Cache",
    "$env:APPDATA\Slack\GPUCache",
    "$env:APPDATA\Slack\blob_storage",
    "$env:APPDATA\Slack\IndexedDB",
    "$env:APPDATA\Slack\Local Storage",
    "$env:APPDATA\Slack\tmp",
    "$env:APPDATA\Slack\logs"
)
$slackFreed = 0
foreach ($path in $slackCachePaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue
        $size  = if ($files -and $files.Count -gt 0) { [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1) } else { 0 }
        Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
        $slackFreed += $size
    }
}
OK "Slack cache cleared (~${slackFreed} MB)."

# ============================================================
# 13. CLEAR OUTLOOK CACHE
# ============================================================
Step "Clearing Outlook cache..."
$outlookCachePaths = @(
    "$env:LOCALAPPDATA\Microsoft\Outlook\RoamCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Temporary Internet Files\Content.Outlook"
)
$outlookFreed = 0
foreach ($path in $outlookCachePaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue
        $size  = if ($files -and $files.Count -gt 0) { [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1) } else { 0 }
        Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
        $outlookFreed += $size
    }
}
OK "Outlook cache cleared (~${outlookFreed} MB)."

# ============================================================
# 14. CLEAR CISCO VPN CACHE
# ============================================================
Step "Clearing Cisco Secure Client cache..."
$ciscoCachePaths = @(
    "$env:LOCALAPPDATA\Cisco\Cisco Secure Client",
    "$env:APPDATA\Cisco\Cisco Secure Client",
    "$env:ProgramData\Cisco\Cisco Secure Client\Umbrella\logs",
    "$env:ProgramData\Cisco\Cisco Secure Client\logs",
    "$env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\Umbrella\logs"
)
$ciscoFreed = 0
foreach ($path in $ciscoCachePaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match "\.log|\.tmp|\.cache" -or $_.DirectoryName -match "logs|cache|tmp" }
        $size = if ($files -and $files.Count -gt 0) { [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1) } else { 0 }
        $files | Remove-Item -Force -ErrorAction SilentlyContinue
        $ciscoFreed += $size
    }
}
OK "Cisco VPN cache and logs cleared (~${ciscoFreed} MB)."

# ============================================================
# 15. CHECK OVERNIGHT CRITICAL EVENTS
# ============================================================
Step "Checking for overnight critical system events..."
$since          = (Get-Date).AddHours(-12)
$criticalEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1; StartTime=$since} -ErrorAction SilentlyContinue
$appErrors      = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=$since} -MaxEvents 10 -ErrorAction SilentlyContinue |
                  Where-Object { $_.Message -notmatch "VSS|WMI|Defrag" }

if ($criticalEvents -and $criticalEvents.Count -gt 0) {
    Fail "$($criticalEvents.Count) critical system event(s) overnight. Run crashdiag for details."
    $summary += "OVERNIGHT: $($criticalEvents.Count) critical system events found"
} elseif ($appErrors -and $appErrors.Count -gt 0) {
    Warn "$($appErrors.Count) application error(s) overnight. Run crashdiag if apps are behaving oddly."
    $summary += "OVERNIGHT: $($appErrors.Count) app errors found"
} else {
    OK "No critical overnight events found."
    $summary += "OVERNIGHT: Clean - no critical events"
}

# ============================================================
# 16. INTERNET CONNECTIVITY CHECK
# ============================================================
Step "Checking internet connectivity..."
try {
    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 2 -ErrorAction Stop
    $avg  = [math]::Round(($ping | Measure-Object ResponseTime -Average).Average, 0)
    OK "Internet reachable - avg ping ${avg}ms to 8.8.8.8."
    $summary += "INTERNET: Online - ${avg}ms ping"
    if ($avg -gt 150) { Warn "Ping latency is high (${avg}ms). Network may be slow today." }
} catch {
    Fail "Cannot reach internet. Check network connection - run netdiag."
    $summary += "INTERNET: OFFLINE"
}

# ============================================================
# MORNING SUMMARY
# ============================================================
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   MORNING SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

foreach ($s in $summary) {
    $color = if ($s -match "NOT CONNECTED|OFFLINE|critical|ISSUE") { "Red" } `
             elseif ($s -match "low|high|warn|error") { "Yellow" } `
             else { "Green" }
    Write-Host "  $s" -ForegroundColor $color
}

Write-Host ""
if ($issues.Count -gt 0) {
    Write-Host "  ISSUES FOUND ($($issues.Count)):" -ForegroundColor Red
    foreach ($issue in $issues) { Write-Host "  !! $issue" -ForegroundColor Red }
    Write-Host ""
}
if ($warnings.Count -gt 0) {
    Write-Host "  WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
    foreach ($warn in $warnings) { Write-Host "  >> $warn" -ForegroundColor Yellow }
    Write-Host ""
}
if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "  All clear - have a great day!" -ForegroundColor Green
    Write-Host ""
}

Write-Host "  Completed in ${elapsed}s" -ForegroundColor Gray
Write-Host "=============================================" -ForegroundColor Cyan
