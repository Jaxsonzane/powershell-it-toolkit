# ============================================================
#  OutlookRepair.ps1 - Outlook Cache & File Repair
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== OutlookRepair - Outlook Repair & Cleanup ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()

# --- 1. Check if Outlook is Running ---
Write-Host "[1/6] Checking if Outlook is running..." -ForegroundColor Yellow
$outlookProcess = Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue
if ($outlookProcess) {
    Write-Host "     WARNING: Outlook is currently running. Close it before proceeding." -ForegroundColor Red
    Write-Host "     Type 'force' to close Outlook automatically or 'exit' to cancel and close it manually." -ForegroundColor Yellow
    do {
        $closeChoice = Read-Host "     Choice"
    } while ($closeChoice -ne "force" -and $closeChoice -ne "exit")

    if ($closeChoice -eq "force") {
        Stop-Process -Name OUTLOOK -Force
        Start-Sleep -Seconds 3
        Write-Host "     Outlook closed." -ForegroundColor Green
    } else {
        Write-Host "     Please close Outlook and re-run this script." -ForegroundColor Yellow
        exit
    }
} else {
    Write-Host "     Outlook is not running. Good." -ForegroundColor Green
}

# --- 2. Find Outlook Version & Profile ---
Write-Host "`n[2/6] Detecting Outlook installation..." -ForegroundColor Yellow
$outlookPath = @(
    "${env:ProgramFiles}\Microsoft Office\root\Office16\OUTLOOK.EXE",
    "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OUTLOOK.EXE",
    "${env:ProgramFiles}\Microsoft Office\Office16\OUTLOOK.EXE",
    "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OUTLOOK.EXE"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($outlookPath) {
    $version = (Get-Item $outlookPath).VersionInfo.FileVersion
    Write-Host "     Outlook found: $outlookPath" -ForegroundColor Green
    Write-Host "     Version: $version" -ForegroundColor Gray
    $recommendations += "OUTLOOK VERSION: $version found at $outlookPath. If version is outdated, run Microsoft Update or use the Office installer to update."
} else {
    Write-Host "     Outlook not found in standard locations." -ForegroundColor Red
    $recommendations += "OUTLOOK NOT FOUND: Could not find Outlook in standard install paths. It may be installed as Microsoft 365 Apps — check Add/Remove Programs or try running 'outlook.exe' from the Start menu manually."
}

# --- 3. Check OST/PST File Sizes ---
Write-Host "`n[3/6] Checking OST/PST data file sizes..." -ForegroundColor Yellow
$dataFilePaths = @(
    "$env:LOCALAPPDATA\Microsoft\Outlook",
    "$env:USERPROFILE\Documents\Outlook Files"
)
$largeFilesFound = $false
foreach ($path in $dataFilePaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem $path -Include *.ost,*.pst -Recurse -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $sizeMB = [math]::Round($f.Length / 1MB, 1)
            $sizeGB = [math]::Round($f.Length / 1GB, 2)
            $color  = if ($sizeMB -gt 5000) { "Red" } elseif ($sizeMB -gt 2000) { "Yellow" } else { "Green" }
            Write-Host "     $($f.Name) — ${sizeMB} MB" -ForegroundColor $color
            if ($sizeMB -gt 5000) {
                $largeFilesFound = $true
                $recommendations += "LARGE DATA FILE: '$($f.Name)' is ${sizeGB} GB — this is very large and will cause Outlook slowness and potential corruption. Archive old emails in Outlook (File > Cleanup Tools > Archive) and consider enabling AutoArchive. Microsoft recommends keeping OST files under 50 GB."
            } elseif ($sizeMB -gt 2000) {
                $recommendations += "GROWING DATA FILE: '$($f.Name)' is ${sizeGB} GB. Getting large — monitor this and archive older emails to keep it under control."
            }
        }
    }
}
if (-not $largeFilesFound) {
    $recommendations += "OST/PST FILES: Data file sizes look acceptable. No action needed."
}

# --- 4. Clear Outlook Cache ---
Write-Host "`n[4/6] Clearing Outlook cache files..." -ForegroundColor Yellow
$cachePaths = @(
    "$env:LOCALAPPDATA\Microsoft\Outlook\RoamCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Temporary Internet Files\Content.Outlook"
)
$cacheFreed = 0
foreach ($path in $cachePaths) {
    if (Test-Path $path) {
        $size = [math]::Round((Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
        Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
        $cacheFreed += $size
        Write-Host "     Cleared ${size} MB from $path" -ForegroundColor Green
    }
}
if ($cacheFreed -gt 0) {
    $recommendations += "CACHE CLEARED: Cleared ${cacheFreed} MB of Outlook cache. Outlook will rebuild the cache on next launch — autocomplete and some suggestions will be temporarily missing but will repopulate."
} else {
    $recommendations += "CACHE: Outlook cache folders were already empty or not found. No action needed."
}

# --- 5. Run ScanPST (Inbox Repair Tool) ---
Write-Host "`n[5/6] Run Inbox Repair Tool (scanpst.exe)?" -ForegroundColor Yellow
Write-Host "     This scans and repairs corrupted OST/PST files. May take several minutes." -ForegroundColor Gray
Write-Host "     Type 'run' to start or 'skip' to skip." -ForegroundColor Gray
do {
    $scanChoice = Read-Host "     Choice"
} while ($scanChoice -ne "run" -and $scanChoice -ne "skip")

if ($scanChoice -eq "run") {
    $scanPstPath = @(
        "${env:ProgramFiles}\Microsoft Office\root\Office16\SCANPST.EXE",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\SCANPST.EXE",
        "${env:ProgramFiles}\Microsoft Office\Office16\SCANPST.EXE"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($scanPstPath) {
        Write-Host "     Launching ScanPST. Follow the on-screen prompts to scan and repair." -ForegroundColor Gray
        Start-Process $scanPstPath -Wait
        Write-Host "     ScanPST completed." -ForegroundColor Green
        $recommendations += "SCANPST: Inbox Repair Tool was run. If it found errors and repaired them, a backup .bak file was created in the same folder as the data file. Test Outlook after repair — if issues persist, run ScanPST again as multiple passes are sometimes needed."
    } else {
        Write-Host "     ScanPST not found. Office may not be installed in a standard location." -ForegroundColor Red
        $recommendations += "SCANPST NOT FOUND: Could not locate scanpst.exe. Search for it manually or run Outlook in safe mode (outlook.exe /safe) as an alternative diagnostic step."
    }
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
    $recommendations += "SCANPST: Skipped. If Outlook is throwing errors about corrupted data files or missing emails, run scanpst.exe manually — it's located in the Office install folder."
}

# --- 6. Outlook Safe Mode Test ---
Write-Host "`n[6/6] Launch Outlook in Safe Mode to test?" -ForegroundColor Yellow
Write-Host "     Safe mode disables all add-ins — useful for diagnosing crashes caused by add-ins." -ForegroundColor Gray
Write-Host "     Type 'run' to launch or 'skip' to skip." -ForegroundColor Gray
do {
    $safeChoice = Read-Host "     Choice"
} while ($safeChoice -ne "run" -and $safeChoice -ne "skip")

if ($safeChoice -eq "run" -and $outlookPath) {
    Start-Process $outlookPath -ArgumentList "/safe"
    Write-Host "     Outlook launched in Safe Mode." -ForegroundColor Green
    $recommendations += "SAFE MODE: Outlook launched in Safe Mode. If it works fine in safe mode but crashes normally, the issue is an add-in. Disable add-ins one by one via: File > Options > Add-ins > Manage COM Add-ins > Go."
} elseif ($safeChoice -eq "run" -and -not $outlookPath) {
    Write-Host "     Cannot launch — Outlook path not found." -ForegroundColor Red
    $recommendations += "SAFE MODE: Could not launch Outlook in Safe Mode automatically. Try manually: Win+R > outlook.exe /safe"
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
    $recommendations += "SAFE MODE: Skipped. If Outlook keeps crashing, test by running: outlook.exe /safe to rule out add-in conflicts."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "LARGE DATA|NOT FOUND|WARNING|corrupted") { "Red" } elseif ($rec -match "GROWING|Skipped|Getting large|outdated") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== Outlook Repair Complete ===" -ForegroundColor Cyan
