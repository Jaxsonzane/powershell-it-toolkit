# ============================================================
#  RemoteDesktopFix.ps1 - RDP Check & Repair
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== RemoteDesktopFix - RDP Check & Repair ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()

# --- 1. Check if RDP is Enabled ---
Write-Host "[1/6] Checking if RDP is enabled..." -ForegroundColor Yellow
$rdpEnabled = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server").fDenyTSConnections
if ($rdpEnabled -eq 0) {
    Write-Host "     RDP is ENABLED." -ForegroundColor Green
    $recommendations += "RDP STATUS: Remote Desktop is enabled on this machine."
} else {
    Write-Host "     RDP is DISABLED." -ForegroundColor Red
    $recommendations += "RDP DISABLED: Remote Desktop is currently disabled. Run this script with option to enable it, or go to: Settings > System > Remote Desktop and toggle it on. Also ensure the machine is not on a Home edition of Windows (RDP hosting requires Pro or higher)."
}

# --- 2. Enable RDP Option ---
Write-Host "`n[2/6] Enable RDP on this machine?" -ForegroundColor Yellow
Write-Host "     Type 'run' to enable or 'skip' to skip." -ForegroundColor Gray
do {
    $rdpChoice = Read-Host "     Choice"
} while ($rdpChoice -ne "run" -and $rdpChoice -ne "skip")

if ($rdpChoice -eq "run") {
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-Host "     RDP enabled and firewall rule activated." -ForegroundColor Green
    $recommendations += "RDP ENABLED: Remote Desktop has been enabled and the firewall rule activated. Users can now connect using the machine's IP or hostname."
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
}

# --- 3. Check RDP Services ---
Write-Host "`n[3/6] Checking RDP-related services..." -ForegroundColor Yellow
$rdpServices = @(
    @{ Name = "TermService";    Display = "Remote Desktop Services" },
    @{ Name = "SessionEnv";     Display = "Remote Desktop Configuration" },
    @{ Name = "UmRdpService";   Display = "Remote Desktop Device Redirector" }
)
foreach ($svc in $rdpServices) {
    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($s) {
        $color = if ($s.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "     $($svc.Display): $($s.Status)" -ForegroundColor $color
        if ($s.Status -ne "Running") {
            Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
            $s.Refresh()
            if ($s.Status -eq "Running") {
                Write-Host "     Started $($svc.Display) successfully." -ForegroundColor Green
            } else {
                $recommendations += "RDP SERVICE FAILED: '$($svc.Display)' could not be started. Check Event Viewer > Windows Logs > System for errors. Try: sc config $($svc.Name) start= auto && net start $($svc.Name)"
            }
        }
    }
}
$recommendations += "RDP SERVICES: All required RDP services checked and started where needed."

# --- 4. Check Firewall Rules ---
Write-Host "`n[4/6] Checking Windows Firewall RDP rules..." -ForegroundColor Yellow
$fwRules = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
if ($fwRules) {
    foreach ($rule in $fwRules) {
        $color = if ($rule.Enabled -eq "True") { "Green" } else { "Red" }
        Write-Host "     $($rule.DisplayName): $($rule.Enabled)" -ForegroundColor $color
        if ($rule.Enabled -ne "True") {
            $recommendations += "FIREWALL RULE DISABLED: Firewall rule '$($rule.DisplayName)' is disabled. Run: Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' to re-enable all RDP firewall rules."
        }
    }
} else {
    Write-Host "     No RDP firewall rules found." -ForegroundColor Red
    $recommendations += "FIREWALL: No RDP firewall rules found. Run: Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' or manually add a rule for TCP port 3389 in Windows Firewall."
}

# --- 5. Check RDP Port ---
Write-Host "`n[5/6] Checking RDP port (default 3389)..." -ForegroundColor Yellow
$rdpPort = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp").PortNumber
Write-Host "     RDP is configured on port: $rdpPort" -ForegroundColor $(if ($rdpPort -eq 3389) { "Green" } else { "Yellow" })
if ($rdpPort -ne 3389) {
    $recommendations += "CUSTOM RDP PORT: RDP is running on port $rdpPort instead of the default 3389. Users must specify this port when connecting: mstsc /v:hostname:$rdpPort. Make sure the firewall allows this custom port."
} else {
    $recommendations += "RDP PORT: Running on standard port 3389. When connecting, users can use: mstsc /v:$env:COMPUTERNAME or mstsc /v:<IP address>"
}

# --- 6. Check Current RDP Sessions ---
Write-Host "`n[6/6] Current RDP/active sessions..." -ForegroundColor Yellow
$sessions = query session 2>$null
if ($sessions) {
    $sessions | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    $recommendations += "ACTIVE SESSIONS: Active session info shown above. If a user is locked out because the session limit is reached (default 2 concurrent sessions), disconnect idle sessions using: logoff <session ID>."
} else {
    Write-Host "     Could not query sessions." -ForegroundColor Yellow
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "DISABLED|FAILED|No RDP|FIREWALL RULE") { "Red" } elseif ($rec -match "CUSTOM|Could not|Skipped") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== Remote Desktop Fix Complete ===" -ForegroundColor Cyan
