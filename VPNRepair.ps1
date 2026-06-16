# ============================================================
#  VPNRepair.ps1 - Cisco Secure Client / AnyConnect Diagnostic
#  Run as Administrator in PowerShell
#
#  UPDATE THIS before use:
#  Set $vpnProfile below to match your VPN profile name
#  (visible in Cisco Secure Client dropdown when connecting)
# ============================================================

Write-Host "`n=== VPNRepair - Cisco Secure Client Diagnostic ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()
$vpnProfile      = "YOUR_VPN_PROFILE_NAME"   # <-- Update this
$desktopPath     = [Environment]::GetFolderPath("Desktop")
if (-not $desktopPath -or -not (Test-Path $desktopPath)) { $desktopPath = "$env:USERPROFILE\Desktop" }
if (-not (Test-Path $desktopPath)) { New-Item -ItemType Directory -Path $desktopPath -Force | Out-Null }
$logPath         = "$desktopPath\VPNRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$logLines        = @()

function Log($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
    $script:logLines += $msg
}

# --- Locate Cisco Secure Client ---
$cscPaths = @(
    "$env:ProgramFiles\Cisco\Cisco Secure Client",
    "$env:ProgramFiles(x86)\Cisco\Cisco Secure Client",
    "$env:ProgramFiles\Cisco\Cisco AnyConnect Secure Mobility Client",
    "$env:ProgramFiles(x86)\Cisco\Cisco AnyConnect Secure Mobility Client"
)
$cscBase    = $cscPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
$vpncliPath = $null

if ($cscBase) {
    $candidate = Join-Path $cscBase "vpncli.exe"
    if (Test-Path $candidate) { $vpncliPath = $candidate }
}
if (-not $vpncliPath) {
    foreach ($sp in @("$env:ProgramFiles\Cisco", "$env:ProgramFiles(x86)\Cisco")) {
        if (Test-Path $sp) {
            $found = Get-ChildItem $sp -Recurse -Filter "vpncli.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $vpncliPath = $found.FullName; $cscBase = $found.DirectoryName; break }
        }
    }
}
if (-not $vpncliPath) {
    $regPaths = @(
        "HKLM:\SOFTWARE\Cisco\Cisco Secure Client",
        "HKLM:\SOFTWARE\WOW6432Node\Cisco\Cisco Secure Client",
        "HKLM:\SOFTWARE\Cisco\Cisco AnyConnect Secure Mobility Client",
        "HKLM:\SOFTWARE\WOW6432Node\Cisco\Cisco AnyConnect Secure Mobility Client"
    )
    foreach ($reg in $regPaths) {
        $regVal = Get-ItemProperty $reg -ErrorAction SilentlyContinue
        $installPath = if ($regVal.InstallPathWithSlash) { $regVal.InstallPathWithSlash } elseif ($regVal.InstallPath) { $regVal.InstallPath } else { $null }
        if ($installPath) {
            $candidate = Join-Path $installPath "vpncli.exe"
            if (Test-Path $candidate) { $vpncliPath = $candidate; $cscBase = $installPath; break }
        }
    }
}

# ============================================================
# STEP 1 - Detect Installation and Version
# ============================================================
Log "[1/8] Detecting Cisco Secure Client installation..." "Yellow"
if ($cscBase) {
    Log "     Found at: $cscBase" "Green"
    $exeFile = @("vpncli.exe","vpnui.exe","csc_ui.exe") | ForEach-Object { Join-Path $cscBase $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exeFile) {
        $ver = (Get-Item $exeFile).VersionInfo.FileVersion
        Log "     Version: $ver" "Gray"
        $versionNum = [version]($ver -replace '[^0-9\.]','')
        if ($versionNum.Major -lt 5) {
            Log "     WARNING: Version $ver is outdated. Cisco Secure Client 5.x is current." "Red"
            $recommendations += "OUTDATED VERSION: Cisco Secure Client $ver is below 5.x. Contact your IT team to get the latest installer."
        } else {
            Log "     Version is current (5.x or higher)." "Green"
            $recommendations += "CISCO VERSION: $ver installed at $cscBase. Version is current."
        }
    }
} else {
    Log "     ERROR: Cisco Secure Client not found." "Red"
    $recommendations += "NOT INSTALLED: Cisco Secure Client not found. Reinstall from your organization's software portal."
}

# ============================================================
# STEP 2 - Check Cisco Services
# ============================================================
Log "`n[2/8] Checking Cisco Secure Client services..." "Yellow"
$ciscoServices = @(
    @{ Name = "vpnagent";          Display = "VPN Agent (core - must be running)" },
    @{ Name = "csc_umbrellaagent"; Display = "Cisco Umbrella Agent" },
    @{ Name = "aciseposture";      Display = "ISE Posture" },
    @{ Name = "csscan";            Display = "Secure Client Scanner" }
)
$servicesFailed = @()
foreach ($svc in $ciscoServices) {
    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($s) {
        Log "     $($svc.Display): $($s.Status)" $(if ($s.Status -eq "Running") { "Green" } else { "Red" })
        if ($s.Status -ne "Running") { $servicesFailed += $svc.Name }
    }
}
if ($servicesFailed.Count -gt 0) {
    $recommendations += "SERVICES DOWN: $($servicesFailed -join ', ') are not running. Script will restart them in step 6."
} else {
    $recommendations += "SERVICES: All Cisco services are running normally."
}

# ============================================================
# STEP 3 - Check VPN Connection Status
# ============================================================
Log "`n[3/8] Checking current VPN connection status..." "Yellow"
$vpnConnected = $false
if ($vpncliPath) {
    $stateResult = & $vpncliPath state 2>$null
    if ($stateResult -match "Connected") {
        $vpnConnected = $true
        Log "     VPN Status: CONNECTED to $vpnProfile" "Green"
        $recommendations += "VPN STATUS: Already connected to $vpnProfile."
    } else {
        Log "     VPN Status: DISCONNECTED" "Red"
        $recommendations += "VPN DISCONNECTED: Not connected. Steps 6 and 7 will fix common causes."
    }
} else {
    Log "     Could not check VPN state - vpncli.exe not found." "Yellow"
}

# ============================================================
# STEP 4 - Check Umbrella
# ============================================================
Log "`n[4/8] Checking Cisco Umbrella..." "Yellow"
$umbrella = Get-Service -Name "csc_umbrellaagent" -ErrorAction SilentlyContinue
if ($umbrella -and $umbrella.Status -eq "Running") {
    Log "     Umbrella: Running" "Green"
    $recommendations += "UMBRELLA: Cisco Umbrella DNS security is active."
} else {
    Log "     Umbrella: Not running" "Yellow"
    $recommendations += "UMBRELLA: Cisco Umbrella is not running. Will be restarted in step 6."
}

# ============================================================
# STEP 5 - Network Health Check
# ============================================================
Log "`n[5/8] Checking network health..." "Yellow"

$activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($a in $activeAdapters) {
    Log "     Adapter UP: $($a.Name) - $($a.InterfaceDescription)" "Gray"
}

$defaultRoutes = Get-NetRoute | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }
if ($defaultRoutes.Count -gt 1) {
    Log "     WARNING: $($defaultRoutes.Count) default routes detected - can cause VPN traffic to leak." "Red"
    foreach ($r in $defaultRoutes) {
        Log "     Route: $($r.DestinationPrefix) via $($r.NextHop) | Interface: $($r.InterfaceAlias) | Metric: $($r.RouteMetric)" "Gray"
    }
    $recommendations += "ROUTE CONFLICT: $($defaultRoutes.Count) default routes detected. Disable Wi-Fi while on ethernet to avoid VPN conflicts."
} else {
    Log "     No conflicting routes detected." "Green"
    $recommendations += "NETWORK: No route conflicts detected."
}

$dnsOK = $true
foreach ($h in @("google.com", "microsoft.com")) {
    try {
        $ip = [System.Net.Dns]::GetHostAddresses($h) | Select-Object -First 1
        Log "     DNS $h -> $($ip.IPAddressToString)" "Gray"
    } catch {
        Log "     DNS FAILED for $h" "Red"
        $dnsOK = $false
    }
}
if (-not $dnsOK) {
    $recommendations += "DNS FAILURE: DNS resolution failing. Run: ipconfig /flushdns and retry."
} else {
    $recommendations += "DNS: DNS resolution is working correctly."
}

try {
    $http = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    Log "     Internet connectivity: OK (HTTP $($http.StatusCode))" "Green"
    $recommendations += "INTERNET: Internet connectivity confirmed."
} catch {
    Log "     Internet connectivity: FAILED" "Red"
    $recommendations += "NO INTERNET: Internet check failed. VPN cannot connect without internet. Run NetDiag.ps1."
}

# ============================================================
# STEP 6 - Check Cisco Logs for Errors
# ============================================================
Log "`n[6/8] Checking Cisco Secure Client logs for errors..." "Yellow"
$logDirs = @(
    "$env:ProgramData\Cisco\Cisco Secure Client\logs",
    "$env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\logs",
    "$env:LOCALAPPDATA\Cisco\Cisco Secure Client\logs"
)
$logErrorsFound = $false
foreach ($logDir in $logDirs) {
    if (Test-Path $logDir) {
        $logFiles = Get-ChildItem $logDir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 2
        foreach ($lf in $logFiles) {
            $lastLines = Get-Content $lf.FullName -Tail 80 -ErrorAction SilentlyContinue
            $errors    = $lastLines | Where-Object { $_ -match "error|fail|disconnect|timeout|certificate|auth|TLS|handshake" }
            if ($errors) {
                $logErrorsFound = $true
                Log "     Errors in $($lf.Name):" "Red"
                $errors | Select-Object -Last 5 | ForEach-Object { Log "       $_" "Red" }
                if ($errors -match "certificate") {
                    $recommendations += "CERTIFICATE ERROR: Certificate errors in Cisco logs. Run certmgr.msc and check Personal > Certificates for expired certs. Contact your IT team if cert needs reissuing."
                }
                if ($errors -match "TLS|handshake") {
                    $recommendations += "TLS ERROR: TLS handshake failures detected. Try updating Cisco Secure Client and check that port 443 is not blocked."
                }
                if ($errors -match "auth") {
                    $recommendations += "AUTH ERROR: Authentication errors detected. Verify your credentials by logging into your VPN portal in a browser."
                }
            }
        }
    }
}
if (-not $logErrorsFound) {
    Log "     No critical errors found in Cisco logs." "Green"
    $recommendations += "LOGS: No critical errors in Cisco Secure Client logs."
}

# ============================================================
# STEP 7 - Apply Fixes
# ============================================================
Log "`n[7/8] Applying fixes..." "Yellow"

Log "     Flushing DNS cache..." "Gray"
ipconfig /flushdns | Out-Null
Log "     DNS flushed." "Green"

Log "     Resetting Winsock..." "Gray"
netsh winsock reset | Out-Null
Log "     Winsock reset." "Green"

Log "     Resetting TCP/IP stack..." "Gray"
netsh int ip reset | Out-Null
Log "     TCP/IP reset." "Green"

Log "     Restarting Cisco Secure Client services..." "Gray"
$svcList = @("vpnagent", "csc_umbrellaagent", "aciseposture", "csscan")
foreach ($svc in $svcList) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Service -Name $svc -ErrorAction SilentlyContinue
        $s.Refresh()
        Log "     ${svc}: $($s.Status)" $(if ($s.Status -eq "Running") { "Green" } else { "Red" })
    }
}

Log "     Clearing Cisco profile cache..." "Gray"
$profileCachePaths = @(
    "$env:ProgramData\Cisco\Cisco Secure Client\Profile",
    "$env:AppData\Cisco\Cisco Secure Client\Profile",
    "$env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\Profile"
)
foreach ($pc in $profileCachePaths) {
    if (Test-Path $pc) {
        Get-ChildItem $pc -Filter "*.xml" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $vpnProfile } | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Log "     Removed stale profile: $($_.Name)" "Gray"
        }
    }
}

Log "     All fixes applied." "Green"
$recommendations += "FIXES APPLIED: DNS flushed, Winsock reset, TCP/IP reset, Cisco services restarted, stale profile cache cleared. Open Cisco Secure Client and connect to '$vpnProfile'."

# ============================================================
# STEP 8 - Final Status Check
# ============================================================
Log "`n[8/8] Final status check..." "Yellow"

$allServicesUp = $true
foreach ($svc in $svcList) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne "Running") { $allServicesUp = $false }
}

if ($allServicesUp) {
    Log "     All Cisco services running after restart." "Green"
} else {
    Log "     WARNING: One or more Cisco services failed to restart." "Red"
    $recommendations += "SERVICE RESTART FAILED: One or more Cisco services could not restart. Try rebooting the machine."
}

if ($vpncliPath) {
    $finalState = & $vpncliPath state 2>$null
    if ($finalState -match "Connected") {
        Log "     VPN: Connected." "Green"
    } else {
        Log "     VPN: Not connected. Open Cisco Secure Client and click Connect." "Yellow"
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "VPN fixes have been applied.`n`nPlease open Cisco Secure Client and connect to:`n`n'$vpnProfile'`n`nIf it still won't connect, check the Recommended Actions for specific errors.",
            "Action Required - Connect to VPN",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
}

# ============================================================
# Recommended Actions
# ============================================================
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "FAILED|ERROR|DOWN|DISCONNECTED|OUTDATED|CONFLICT|WARNING|CERTIFICATE|TLS|AUTH|NO INTERNET") { "Red" } `
             elseif ($rec -match "Skipped|UMBRELLA|DISCONNECTED") { "Yellow" } `
             else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

$script:logLines | Out-File -FilePath $logPath -Encoding UTF8
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
Write-Host "`n=== VPN Repair Complete ===" -ForegroundColor Cyan
