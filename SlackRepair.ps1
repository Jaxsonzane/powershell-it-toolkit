# ============================================================
#  SlackRepair.ps1 - Slack Diagnostic & Repair
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== SlackRepair - Slack Diagnostic & Repair ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()
$slackRunning = $false

# --- 1. Check if Slack is Running ---
Write-Host "[1/9] Checking if Slack is running..." -ForegroundColor Yellow
$slackProcess = Get-Process -Name slack -ErrorAction SilentlyContinue
if ($slackProcess) {
    $slackRunning = $true
    Write-Host "     WARNING: Slack is currently running." -ForegroundColor Red
    Write-Host "     Type 'force' to close Slack automatically or 'exit' to cancel." -ForegroundColor Yellow
    do {
        $closeChoice = Read-Host "     Choice"
    } while ($closeChoice -ne "force" -and $closeChoice -ne "exit")

    if ($closeChoice -eq "force") {
        Get-Process -Name slack -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 3
        Write-Host "     Slack closed." -ForegroundColor Green
    } else {
        Write-Host "     Please close Slack and re-run this script." -ForegroundColor Yellow
        exit
    }
} else {
    Write-Host "     Slack is not running. Good." -ForegroundColor Green
}

# --- 2. Detect Slack Installation ---
Write-Host "`n[2/9] Detecting Slack installation..." -ForegroundColor Yellow
$slackPaths = @(
    "$env:LOCALAPPDATA\slack\slack.exe",
    "$env:ProgramFiles\Slack\slack.exe",
    "$env:ProgramFiles(x86)\Slack\slack.exe"
)
$slackExe = $slackPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($slackExe) {
    $version = (Get-Item $slackExe).VersionInfo.FileVersion
    Write-Host "     Slack found: $slackExe" -ForegroundColor Green
    Write-Host "     Version: $version" -ForegroundColor Gray
    $recommendations += "SLACK VERSION: $version installed at $slackExe. If Slack is behaving oddly, check for updates in Slack > Help > Check for Updates."
} else {
    Write-Host "     Slack executable not found in standard locations." -ForegroundColor Red
    $recommendations += "SLACK NOT FOUND: Could not locate slack.exe. Slack may not be installed or may be installed in a non-standard location. Check Add/Remove Programs or reinstall from https://slack.com/downloads/windows."
}

# --- 3. Check Cache Size ---
Write-Host "`n[3/9] Checking Slack cache size..." -ForegroundColor Yellow
$cachePaths = @(
    "$env:APPDATA\Slack\Cache",
    "$env:APPDATA\Slack\Code Cache",
    "$env:APPDATA\Slack\GPUCache",
    "$env:APPDATA\Slack\blob_storage",
    "$env:APPDATA\Slack\databases",
    "$env:APPDATA\Slack\IndexedDB",
    "$env:APPDATA\Slack\Local Storage"
)
$totalCacheMB = 0
foreach ($path in $cachePaths) {
    if (Test-Path $path) {
        $size = [math]::Round((Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
        $totalCacheMB += $size
        Write-Host "     $([System.IO.Path]::GetFileName($path)): ${size} MB" -ForegroundColor $(if ($size -gt 500) { "Red" } elseif ($size -gt 200) { "Yellow" } else { "Gray" })
    }
}
Write-Host "     Total cache size: ${totalCacheMB} MB" -ForegroundColor $(if ($totalCacheMB -gt 1000) { "Red" } elseif ($totalCacheMB -gt 500) { "Yellow" } else { "Green" })

if ($totalCacheMB -gt 1000) {
    $recommendations += "CACHE CRITICAL: Slack cache is ${totalCacheMB} MB — very large. This is likely causing slowness, high memory usage, and crashes. Clear it using the option below."
} elseif ($totalCacheMB -gt 500) {
    $recommendations += "CACHE LARGE: Slack cache is ${totalCacheMB} MB — getting large. Consider clearing it to improve performance."
} else {
    $recommendations += "CACHE: Slack cache is ${totalCacheMB} MB — within normal range."
}

# --- 4. Check Log Size ---
Write-Host "`n[4/9] Checking Slack log size..." -ForegroundColor Yellow
$logPath = "$env:APPDATA\Slack\logs"
if (Test-Path $logPath) {
    $logSizeMB = [math]::Round((Get-ChildItem $logPath -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host "     Log folder size: ${logSizeMB} MB" -ForegroundColor $(if ($logSizeMB -gt 200) { "Yellow" } else { "Gray" })
    if ($logSizeMB -gt 200) {
        $recommendations += "LOGS: Slack log folder is ${logSizeMB} MB. Large log files can slow Slack down. These will be cleared in the cleanup step."
    } else {
        $recommendations += "LOGS: Slack log folder is ${logSizeMB} MB — normal size."
    }
} else {
    Write-Host "     Log folder not found." -ForegroundColor Gray
}

# --- 5. Check Auto-Start ---
Write-Host "`n[5/9] Checking if Slack is set to auto-start..." -ForegroundColor Yellow
$startupReg = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
$slackStartup = $startupReg.PSObject.Properties | Where-Object { $_.Name -match "Slack" -or $_.Value -match "slack" }
if ($slackStartup) {
    Write-Host "     Slack is set to auto-start at login." -ForegroundColor Yellow
    Write-Host "     Path: $($slackStartup.Value)" -ForegroundColor Gray
    $recommendations += "AUTO-START: Slack is configured to launch at login. If boot times are slow, disable this in Slack > Preferences > Advanced > uncheck 'Launch app on login', or remove the registry entry under HKCU\Software\Microsoft\Windows\CurrentVersion\Run."
} else {
    Write-Host "     Slack is not set to auto-start." -ForegroundColor Green
    $recommendations += "AUTO-START: Slack is not set to auto-start. No impact on boot time."
}

# --- 6. Check Event Log for Slack Crashes ---
Write-Host "`n[6/9] Checking Event Log for recent Slack crashes..." -ForegroundColor Yellow
$slackCrashes = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match "slack" }
if ($slackCrashes) {
    Write-Host "     $($slackCrashes.Count) Slack crash event(s) found:" -ForegroundColor Red
    foreach ($e in $slackCrashes | Select-Object -First 5) {
        Write-Host "     [$($e.TimeCreated)] $($e.Message.Split("`n")[0])" -ForegroundColor Red
    }
    $recommendations += "CRASH EVENTS: $($slackCrashes.Count) Slack crash(es) found in Event Log. This confirms Slack is unstable on this machine. Clear the cache first — if crashes continue after that, try reinstalling Slack completely."
} else {
    Write-Host "     No Slack crash events found in Event Log." -ForegroundColor Green
    $recommendations += "CRASH EVENTS: No Slack crashes found in Event Log. Slack appears stable."
}

# --- 7. Clear Slack Cache ---
Write-Host "`n[7/9] Clear Slack cache?" -ForegroundColor Yellow
Write-Host "     This fixes most Slack slowness, high memory usage, and crash issues." -ForegroundColor Gray
Write-Host "     Type 'run' to clear or 'skip' to skip." -ForegroundColor Gray
do {
    $cacheChoice = Read-Host "     Choice"
} while ($cacheChoice -ne "run" -and $cacheChoice -ne "skip")

if ($cacheChoice -eq "run") {
    $freedMB = 0
    foreach ($path in $cachePaths) {
        if (Test-Path $path) {
            $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue
            $size = if ($files -and $files.Count -gt 0) { [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1) } else { 0 }
            Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
            $freedMB += $size
        }
    }
    # Clear logs too
    if (Test-Path "$env:APPDATA\Slack\logs") {
        Remove-Item "$env:APPDATA\Slack\logs\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "     Cleared ~${freedMB} MB of Slack cache and logs." -ForegroundColor Green
    $recommendations += "CACHE CLEARED: Cleared ~${freedMB} MB of Slack cache. Slack will rebuild its cache on next launch — this is normal. Expect a slightly slower first load."
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
    $recommendations += "CACHE: Cache clear was skipped. If Slack is slow or crashing, clearing the cache is the recommended first fix."
}

# --- 8. Nuclear Reset Option (Clear all AppData) ---
Write-Host "`n[8/9] Full Slack AppData reset (nuclear option)?" -ForegroundColor Yellow
Write-Host "     WARNING: This clears ALL Slack local data including preferences and login sessions." -ForegroundColor Red
Write-Host "     The user will need to log back into all workspaces after this." -ForegroundColor Red
Write-Host "     Only use this if cache clearing didn't fix the issue." -ForegroundColor Yellow
Write-Host "     Type 'run' to reset or 'skip' to skip." -ForegroundColor Gray
do {
    $nuclearChoice = Read-Host "     Choice"
} while ($nuclearChoice -ne "run" -and $nuclearChoice -ne "skip")

if ($nuclearChoice -eq "run") {
    $slackAppData = "$env:APPDATA\Slack"
    if (Test-Path $slackAppData) {
        $appDataFiles = Get-ChildItem $slackAppData -Recurse -File -ErrorAction SilentlyContinue
        $totalSize = if ($appDataFiles -and $appDataFiles.Count -gt 0) { [math]::Round(($appDataFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 1) } else { 0 }
        Remove-Item "$slackAppData\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "     Cleared ~${totalSize} MB from Slack AppData." -ForegroundColor Green
        $recommendations += "FULL RESET: Slack AppData fully cleared (~${totalSize} MB). The user will need to log back into all Slack workspaces on next launch. This should resolve any persistent issues that cache clearing alone did not fix."
    } else {
        Write-Host "     Slack AppData folder not found." -ForegroundColor Yellow
        $recommendations += "FULL RESET: Slack AppData folder not found — may have already been cleared or Slack was never fully set up on this machine."
    }
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
    $recommendations += "FULL RESET: Skipped. If Slack continues to crash after cache clearing, come back and run this option — it's the most thorough fix short of a full reinstall."
}

# --- 9. Relaunch Slack ---
Write-Host "`n[9/9] Relaunch Slack now?" -ForegroundColor Yellow
Write-Host "     Type 'run' to launch or 'skip' to skip." -ForegroundColor Gray
do {
    $launchChoice = Read-Host "     Choice"
} while ($launchChoice -ne "run" -and $launchChoice -ne "skip")

if ($launchChoice -eq "run" -and $slackExe) {
    Start-Process $slackExe
    Write-Host "     Slack launched." -ForegroundColor Green
    $recommendations += "RELAUNCH: Slack was relaunched. Monitor for a few minutes to confirm the issue is resolved."
} elseif ($launchChoice -eq "run" -and -not $slackExe) {
    Write-Host "     Cannot launch — Slack path not found." -ForegroundColor Red
    $recommendations += "RELAUNCH: Could not relaunch Slack automatically — path not found. Launch it manually from the Start menu."
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "CRITICAL|CRASH EVENTS.*confirm|NOT FOUND|WARNING|Full reset") { "Red" } elseif ($rec -match "LARGE|AUTO-START|Skipped|slow") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== Slack Repair Complete ===" -ForegroundColor Cyan
