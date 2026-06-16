# ============================================================
#  BrowserRepair.ps1 - Browser Diagnostic & Repair
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== BrowserRepair - Browser Diagnostic & Repair ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()

# ============================================================
# HELPER FUNCTIONS
# ============================================================
function Get-FolderSizeMB($path) {
    if (Test-Path $path) {
        $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue
        if ($files -and $files.Count -gt 0) {
            return [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
        }
    }
    return 0
}

function Clear-Folder($path) {
    if (Test-Path $path) {
        Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
# STEP 1 - Detect Installed Browsers
# ============================================================
Write-Host "[1/9] Detecting installed browsers..." -ForegroundColor Yellow

$browsers = @{}

# Chrome
$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chromeExe = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($chromeExe) {
    $browsers["Chrome"] = @{ Path = $chromeExe; Version = (Get-Item $chromeExe).VersionInfo.FileVersion }
    Write-Host "     Google Chrome: $($browsers["Chrome"].Version)" -ForegroundColor Green
} else {
    Write-Host "     Google Chrome: Not found" -ForegroundColor Gray
}

# Edge
$edgePaths = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"
)
$edgeExe = $edgePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($edgeExe) {
    $browsers["Edge"] = @{ Path = $edgeExe; Version = (Get-Item $edgeExe).VersionInfo.FileVersion }
    Write-Host "     Microsoft Edge: $($browsers["Edge"].Version)" -ForegroundColor Green
} else {
    Write-Host "     Microsoft Edge: Not found" -ForegroundColor Gray
}

# Firefox
$firefoxPaths = @(
    "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
    "$env:ProgramFiles(x86)\Mozilla Firefox\firefox.exe"
)
$firefoxExe = $firefoxPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($firefoxExe) {
    $browsers["Firefox"] = @{ Path = $firefoxExe; Version = (Get-Item $firefoxExe).VersionInfo.FileVersion }
    Write-Host "     Mozilla Firefox: $($browsers["Firefox"].Version)" -ForegroundColor Green
} else {
    Write-Host "     Mozilla Firefox: Not found" -ForegroundColor Gray
}

if ($browsers.Count -eq 0) {
    Write-Host "     No supported browsers found." -ForegroundColor Red
    $recommendations += "NO BROWSERS: No supported browsers detected. Install Chrome, Edge, or Firefox."
} else {
    $recommendations += "BROWSERS DETECTED: Found $($browsers.Count) browser(s) — $($browsers.Keys -join ', '). All versions noted above."
}

# ============================================================
# STEP 2 - Check Cache Sizes
# ============================================================
Write-Host "`n[2/9] Checking browser cache sizes..." -ForegroundColor Yellow

$cacheSizes = @{}

# Chrome cache
$chromeCachePaths = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\ShaderCache"
)
$chromeCacheMB = 0
foreach ($p in $chromeCachePaths) { $chromeCacheMB += Get-FolderSizeMB $p }
$cacheSizes["Chrome"] = $chromeCacheMB
if ($chromeExe) {
    Write-Host "     Chrome cache:  ${chromeCacheMB} MB" -ForegroundColor $(if ($chromeCacheMB -gt 1000) { "Red" } elseif ($chromeCacheMB -gt 500) { "Yellow" } else { "Green" })
}

# Edge cache
$edgeCachePaths = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\ShaderCache"
)
$edgeCacheMB = 0
foreach ($p in $edgeCachePaths) { $edgeCacheMB += Get-FolderSizeMB $p }
$cacheSizes["Edge"] = $edgeCacheMB
if ($edgeExe) {
    Write-Host "     Edge cache:    ${edgeCacheMB} MB" -ForegroundColor $(if ($edgeCacheMB -gt 1000) { "Red" } elseif ($edgeCacheMB -gt 500) { "Yellow" } else { "Green" })
}

# Firefox cache
$firefoxCacheMB = 0
$ffProfileBase = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffProfileBase) {
    $ffProfiles = Get-ChildItem $ffProfileBase -Directory -ErrorAction SilentlyContinue
    foreach ($ffp in $ffProfiles) {
        $firefoxCacheMB += Get-FolderSizeMB "$($ffp.FullName)\cache2"
    }
}
$cacheSizes["Firefox"] = $firefoxCacheMB
if ($firefoxExe) {
    Write-Host "     Firefox cache: ${firefoxCacheMB} MB" -ForegroundColor $(if ($firefoxCacheMB -gt 1000) { "Red" } elseif ($firefoxCacheMB -gt 500) { "Yellow" } else { "Green" })
}

foreach ($browser in $cacheSizes.Keys) {
    $size = $cacheSizes[$browser]
    if ($size -gt 1000) {
        $recommendations += "CACHE CRITICAL ($browser): Cache is ${size} MB — very large. Clear it to improve performance and free disk space."
    } elseif ($size -gt 500) {
        $recommendations += "CACHE LARGE ($browser): Cache is ${size} MB — getting large. Consider clearing it."
    }
}
if (-not ($cacheSizes.Values | Where-Object { $_ -gt 500 })) {
    $recommendations += "CACHE: All browser caches are within normal range. No action needed."
}

# ============================================================
# STEP 3 - Check Auto-Start
# ============================================================
Write-Host "`n[3/9] Checking browser auto-start entries..." -ForegroundColor Yellow
$startupReg = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
$browserStartups = $startupReg.PSObject.Properties | Where-Object {
    $_.Value -match "chrome|msedge|firefox"
}
if ($browserStartups) {
    foreach ($s in $browserStartups) {
        Write-Host "     Auto-start found: $($s.Name) -> $($s.Value)" -ForegroundColor Yellow
        $recommendations += "AUTO-START: '$($s.Name)' is set to launch at login. If boot times are slow, disable this in the browser settings or remove from Task Manager > Startup tab."
    }
} else {
    Write-Host "     No browsers set to auto-start." -ForegroundColor Green
    $recommendations += "AUTO-START: No browsers are set to auto-start. No impact on boot time."
}

# ============================================================
# STEP 4 - Check Event Log for Browser Crashes
# ============================================================
Write-Host "`n[4/9] Checking Event Log for recent browser crashes..." -ForegroundColor Yellow
$crashEvents = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000} -MaxEvents 100 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match "chrome|msedge|firefox" }

if ($crashEvents) {
    $crashCounts = @{}
    foreach ($e in $crashEvents) {
        $name = if ($e.Message -match "chrome") { "Chrome" } elseif ($e.Message -match "msedge") { "Edge" } else { "Firefox" }
        $crashCounts[$name] = ($crashCounts[$name] + 1)
    }
    foreach ($b in $crashCounts.Keys) {
        Write-Host "     $b`: $($crashCounts[$b]) crash event(s) found" -ForegroundColor Red
        $recommendations += "CRASHES ($b): $($crashCounts[$b]) crash event(s) found in Event Log. Clear cache first — if crashes continue, disable extensions one by one or reset the browser profile."
    }
} else {
    Write-Host "     No browser crash events found." -ForegroundColor Green
    $recommendations += "CRASH EVENTS: No browser crashes found in Event Log. Browsers appear stable."
}

# ============================================================
# STEP 5 - Check for Known Problematic Extensions
# ============================================================
Write-Host "`n[5/9] Checking for extensions..." -ForegroundColor Yellow

# Chrome extensions
$chromeExtPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
if (Test-Path $chromeExtPath) {
    $chromeExts = Get-ChildItem $chromeExtPath -Directory -ErrorAction SilentlyContinue
    Write-Host "     Chrome extensions installed: $($chromeExts.Count)" -ForegroundColor $(if ($chromeExts.Count -gt 15) { "Yellow" } else { "Gray" })
    if ($chromeExts.Count -gt 15) {
        $recommendations += "EXTENSIONS (Chrome): $($chromeExts.Count) extensions installed — high number. Too many extensions slow Chrome down significantly. Review and disable unused ones at chrome://extensions."
    } else {
        $recommendations += "EXTENSIONS (Chrome): $($chromeExts.Count) extensions installed — reasonable. If Chrome is slow, try disabling all extensions temporarily at chrome://extensions to rule them out."
    }
}

# Edge extensions
$edgeExtPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
if (Test-Path $edgeExtPath) {
    $edgeExts = Get-ChildItem $edgeExtPath -Directory -ErrorAction SilentlyContinue
    Write-Host "     Edge extensions installed:   $($edgeExts.Count)" -ForegroundColor $(if ($edgeExts.Count -gt 15) { "Yellow" } else { "Gray" })
    if ($edgeExts.Count -gt 15) {
        $recommendations += "EXTENSIONS (Edge): $($edgeExts.Count) extensions installed — high number. Review and disable unused ones at edge://extensions."
    }
}

# ============================================================
# STEP 6 - Kill Hung Browser Processes
# ============================================================
Write-Host "`n[6/9] Checking for hung browser processes..." -ForegroundColor Yellow
$browserProcs = Get-Process | Where-Object { $_.Name -match "chrome|msedge|firefox" } -ErrorAction SilentlyContinue
if ($browserProcs) {
    Write-Host "     Active browser processes found:" -ForegroundColor Yellow
    $browserProcs | Group-Object Name | ForEach-Object {
        Write-Host "     $($_.Name): $($_.Count) process(es)" -ForegroundColor Gray
    }
    Write-Host "`n     Kill all browser processes? Type 'run' to kill or 'skip' to skip." -ForegroundColor Yellow
    do { $killChoice = Read-Host "     Choice" } while ($killChoice -ne "run" -and $killChoice -ne "skip")

    if ($killChoice -eq "run") {
        Get-Process | Where-Object { $_.Name -match "chrome|msedge|firefox" } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Host "     All browser processes killed." -ForegroundColor Green
        $recommendations += "PROCESSES KILLED: All browser processes were terminated. Relaunch your browser to confirm it opens cleanly."
    } else {
        Write-Host "     Skipped." -ForegroundColor Gray
    }
} else {
    Write-Host "     No active browser processes found." -ForegroundColor Green
    $recommendations += "PROCESSES: No active browser processes running. Good."
}

# ============================================================
# STEP 7 - Clear Browser Cache
# ============================================================
Write-Host "`n[7/9] Clear browser cache?" -ForegroundColor Yellow
Write-Host "     Select which browsers to clear:" -ForegroundColor Gray
Write-Host "     Type 'all' to clear all, 'chrome', 'edge', 'firefox', or 'skip'." -ForegroundColor Gray
do {
    $clearChoice = Read-Host "     Choice"
} while ($clearChoice -notin @("all", "chrome", "edge", "firefox", "skip"))

if ($clearChoice -ne "skip") {
    $totalFreedMB = 0

    if ($clearChoice -eq "all" -or $clearChoice -eq "chrome") {
        $freed = 0
        foreach ($p in $chromeCachePaths) { $s = Get-FolderSizeMB $p; Clear-Folder $p; $freed += $s }
        Write-Host "     Chrome: Cleared ~${freed} MB" -ForegroundColor Green
        $totalFreedMB += $freed
    }
    if ($clearChoice -eq "all" -or $clearChoice -eq "edge") {
        $freed = 0
        foreach ($p in $edgeCachePaths) { $s = Get-FolderSizeMB $p; Clear-Folder $p; $freed += $s }
        Write-Host "     Edge: Cleared ~${freed} MB" -ForegroundColor Green
        $totalFreedMB += $freed
    }
    if ($clearChoice -eq "all" -or $clearChoice -eq "firefox") {
        $freed = 0
        if (Test-Path $ffProfileBase) {
            $ffProfiles = Get-ChildItem $ffProfileBase -Directory -ErrorAction SilentlyContinue
            foreach ($ffp in $ffProfiles) {
                $s = Get-FolderSizeMB "$($ffp.FullName)\cache2"
                Clear-Folder "$($ffp.FullName)\cache2"
                $freed += $s
            }
        }
        Write-Host "     Firefox: Cleared ~${freed} MB" -ForegroundColor Green
        $totalFreedMB += $freed
    }
    $recommendations += "CACHE CLEARED: Cleared ~${totalFreedMB} MB of browser cache. Browsers will rebuild cache on next launch — first page loads may be slightly slower."
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
    $recommendations += "CACHE: Cache clear skipped. If browsers are slow, clearing cache is the recommended first fix."
}

# ============================================================
# STEP 8 - Reset Browser Flags
# ============================================================
Write-Host "`n[8/9] Reset browser experimental flags to default?" -ForegroundColor Yellow
Write-Host "     Resets chrome://flags and edge://flags — fixes crashes caused by bad experimental settings." -ForegroundColor Gray
Write-Host "     Type 'run' to reset or 'skip' to skip." -ForegroundColor Gray
do {
    $flagChoice = Read-Host "     Choice"
} while ($flagChoice -ne "run" -and $flagChoice -ne "skip")

if ($flagChoice -eq "run") {
    $flagsReset = $false
    $chromeLocal = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
    $edgeLocal   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"

    foreach ($flagFile in @($chromeLocal, $edgeLocal)) {
        if (Test-Path $flagFile) {
            $browser = if ($flagFile -match "Chrome") { "Chrome" } else { "Edge" }
            try {
                $json = Get-Content $flagFile -Raw | ConvertFrom-Json
                if ($json.browser.enabled_labs_experiments) {
                    $json.browser.enabled_labs_experiments = @()
                    $json | ConvertTo-Json -Depth 20 | Set-Content $flagFile
                    Write-Host "     $browser flags reset to default." -ForegroundColor Green
                    $flagsReset = $true
                } else {
                    Write-Host "     $browser`: No custom flags found." -ForegroundColor Gray
                }
            } catch {
                Write-Host "     $browser`: Could not reset flags — file may be locked." -ForegroundColor Yellow
            }
        }
    }
    if ($flagsReset) {
        $recommendations += "FLAGS RESET: Browser experimental flags cleared. If the browser was crashing due to an unstable experimental feature, this should resolve it."
    } else {
        $recommendations += "FLAGS: No custom experimental flags found in any browser. Nothing to reset."
    }
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
    $recommendations += "FLAGS: Flag reset skipped. If browser crashes persist after cache clearing, try resetting flags at chrome://flags or edge://flags and clicking 'Reset All'."
}

# ============================================================
# STEP 9 - Nuclear Profile Reset
# ============================================================
Write-Host "`n[9/9] Nuclear profile reset?" -ForegroundColor Yellow
Write-Host "     WARNING: This resets the browser profile to factory default." -ForegroundColor Red
Write-Host "     Bookmarks, saved passwords, extensions, and history will be lost." -ForegroundColor Red
Write-Host "     Only use this if all other steps failed." -ForegroundColor Yellow
Write-Host "     Select browser: 'chrome', 'edge', 'firefox', or 'skip'." -ForegroundColor Gray
do {
    $nuclearChoice = Read-Host "     Choice"
} while ($nuclearChoice -notin @("chrome", "edge", "firefox", "skip"))

if ($nuclearChoice -ne "skip") {
    $profilePath = switch ($nuclearChoice) {
        "chrome"  { "$env:LOCALAPPDATA\Google\Chrome\User Data\Default" }
        "edge"    { "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default" }
        "firefox" { $null }
    }

    if ($nuclearChoice -eq "firefox" -and (Test-Path $ffProfileBase)) {
        $ffProfiles = Get-ChildItem $ffProfileBase -Directory -ErrorAction SilentlyContinue
        foreach ($ffp in $ffProfiles) {
            $sizeMB = Get-FolderSizeMB $ffp.FullName
            Remove-Item "$($ffp.FullName)\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "     Firefox profile cleared (~${sizeMB} MB): $($ffp.Name)" -ForegroundColor Green
        }
        $recommendations += "NUCLEAR RESET (Firefox): Firefox profile(s) fully reset. User will need to sign back into sites and re-add extensions on next launch."
    } elseif ($profilePath -and (Test-Path $profilePath)) {
        $sizeMB = Get-FolderSizeMB $profilePath
        # Backup first
        $backupPath = "$profilePath`_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $profilePath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$profilePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "     Profile cleared (~${sizeMB} MB). Backup saved to: $backupPath" -ForegroundColor Green
        $recommendations += "NUCLEAR RESET ($nuclearChoice): Profile fully reset (~${sizeMB} MB cleared). A backup was saved to $backupPath. User will need to sign back into sites and re-add extensions. If you need to restore, copy the backup folder back."
    } else {
        Write-Host "     Profile path not found for $nuclearChoice." -ForegroundColor Red
        $recommendations += "NUCLEAR RESET: Could not find $nuclearChoice profile folder. Browser may not be installed or profile is in a non-standard location."
    }
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
    $recommendations += "NUCLEAR RESET: Skipped. Only use this as a last resort if all other fixes failed."
}

# ============================================================
# Recommended Actions
# ============================================================
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "CRITICAL|CRASHES|WARNING|NOT FOUND") { "Red" } `
             elseif ($rec -match "LARGE|AUTO-START|Skipped|high number") { "Yellow" } `
             else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== Browser Repair Complete ===" -ForegroundColor Cyan
