# ============================================================
#  AppCrashDiag.ps1 - Application Crash Diagnostic
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== AppCrashDiag - Application Crash Diagnostic ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()
$desktopPath = [Environment]::GetFolderPath("Desktop")
if (-not $desktopPath -or -not (Test-Path $desktopPath)) { $desktopPath = "$env:USERPROFILE\Desktop" }
if (-not (Test-Path $desktopPath)) { New-Item -ItemType Directory -Path $desktopPath -Force | Out-Null }
$logPath = "$desktopPath\AppCrashDiag_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$logLines = @()

function Log($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
    $script:logLines += $msg
}

# --- 1. Application Errors (Event ID 1000) ---
Log "[1/5] Pulling last 20 application errors (Event ID 1000)..." "Yellow"
$appErrors = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000} -MaxEvents 20 -ErrorAction SilentlyContinue
if ($appErrors) {
    $crashCounts = @{}
    foreach ($e in $appErrors) {
        $msg = $e.Message -split "`n" | Select-Object -First 3
        Log "     [$($e.TimeCreated)] $($msg[0])" "Red"
        # Count crashes per app
        if ($e.Message -match "Faulting application name: (.+?),") {
            $appName = $Matches[1].Trim()
            $crashCounts[$appName] = ($crashCounts[$appName] + 1)
        }
    }
    # Flag repeat offenders
    foreach ($app in $crashCounts.Keys) {
        if ($crashCounts[$app] -ge 3) {
            $recommendations += "REPEAT CRASHES: '$app' has crashed $($crashCounts[$app]) times recently. This app needs attention — try repairing it via Settings > Apps, reinstalling, or updating it. Check if a recent Windows Update or app update coincides with when crashes started."
        }
    }
} else {
    Log "     No application errors found in Event Log." "Green"
    $recommendations += "APP ERRORS: No application error events (ID 1000) found. The crash may be too recent or Event Log may have been cleared."
}

# --- 2. Application Hangs (Event ID 1002) ---
Log "`n[2/5] Pulling last 10 application hangs (Event ID 1002)..." "Yellow"
$appHangs = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1002} -MaxEvents 10 -ErrorAction SilentlyContinue
if ($appHangs) {
    foreach ($e in $appHangs) {
        Log "     [$($e.TimeCreated)] $($e.Message.Split("`n")[0])" "Yellow"
    }
    $recommendations += "APP HANGS: $($appHangs.Count) application hang event(s) detected. Hangs are often caused by insufficient RAM, a slow disk, or a deadlock in the app. Check RAM usage in Task Manager during the hang and consider increasing virtual memory."
} else {
    Log "     No application hang events found." "Green"
    $recommendations += "APP HANGS: No hang events detected. Good."
}

# --- 3. .NET Runtime Errors (Event ID 1026) ---
Log "`n[3/5] Checking for .NET runtime errors (Event ID 1026)..." "Yellow"
$dotnetErrors = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1026} -MaxEvents 10 -ErrorAction SilentlyContinue
if ($dotnetErrors) {
    foreach ($e in $dotnetErrors) {
        Log "     [$($e.TimeCreated)] $($e.Message.Split("`n")[0])" "Yellow"
    }
    $recommendations += ".NET ERRORS: $($dotnetErrors.Count) .NET runtime error(s) found. Try repairing the .NET Framework via Control Panel > Programs > Turn Windows features on or off, or download the .NET repair tool from Microsoft."
} else {
    Log "     No .NET runtime errors found." "Green"
    $recommendations += ".NET: No .NET runtime errors detected."
}

# --- 4. Windows Error Reporting Dumps ---
Log "`n[4/5] Checking for crash dump files..." "Yellow"
$dumpPaths = @(
    "C:\Windows\Minidump",
    "C:\Windows\MEMORY.DMP",
    "$env:LOCALAPPDATA\CrashDumps",
    "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"
)
$dumpsFound = $false
foreach ($path in $dumpPaths) {
    if (Test-Path $path) {
        $dumps = Get-ChildItem $path -ErrorAction SilentlyContinue
        if ($dumps) {
            $dumpsFound = $true
            Log "     Found $($dumps.Count) dump file(s) at: $path" "Yellow"
            $dumps | Select-Object -Last 3 | ForEach-Object {
                Log "       - $($_.Name) | $($_.LastWriteTime) | $([math]::Round($_.Length/1MB,1)) MB" "Gray"
            }
        }
    }
}
if ($dumpsFound) {
    $recommendations += "CRASH DUMPS: Crash dump files were found. These can be analyzed with WinDbg to get the exact cause of crashes. For blue screens specifically, upload the minidump files from C:\Windows\Minidump to https://www.osronline.com for automated analysis."
} else {
    Log "     No crash dump files found." "Green"
    $recommendations += "CRASH DUMPS: No crash dump files found. If the machine is blue screening, enable dump file creation via: System Properties > Advanced > Startup and Recovery > Write debugging information > Small memory dump."
}

# --- 5. Recent Critical System Events ---
Log "`n[5/5] Recent critical system events (last 10)..." "Yellow"
$criticalEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1} -MaxEvents 10 -ErrorAction SilentlyContinue
if ($criticalEvents) {
    foreach ($e in $criticalEvents) {
        Log "     [$($e.TimeCreated)] $($e.Message.Split("`n")[0])" "Red"
    }
    $recommendations += "CRITICAL EVENTS: $($criticalEvents.Count) critical system event(s) found. These often indicate hardware failures, driver crashes, or kernel-level issues. Review them in Event Viewer > Windows Logs > System filtered by Critical level."
} else {
    Log "     No critical system events found." "Green"
    $recommendations += "SYSTEM EVENTS: No critical system events found. System log looks clean."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "REPEAT|CRASH DUMPS found|CRITICAL|.NET ERRORS|HANGS") { "Red" } elseif ($rec -match "No crash dump|enable|Consider") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

$script:logLines | Out-File -FilePath $logPath -Encoding UTF8
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
Write-Host "`n=== App Crash Diagnostic Complete ===" -ForegroundColor Cyan
