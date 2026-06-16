# ============================================================
#  DiskCleanup.ps1 - Deep Disk Cleanup
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== DiskCleanup - Deep Disk Cleanup ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()
$totalFreedMB = 0

function Get-FolderSizeMB($path) {
    if (Test-Path $path) {
        return [math]::Round((Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
    }
    return 0
}

# --- Disk space before ---
$diskBefore = Get-PSDrive C
$freeBefore = [math]::Round($diskBefore.Free / 1GB, 2)
Write-Host "Disk space before cleanup: ${freeBefore} GB free`n" -ForegroundColor Gray

# --- 1. User Temp Files ---
Write-Host "[1/8] Clearing user temp files..." -ForegroundColor Yellow
$size = Get-FolderSizeMB "$env:TEMP"
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
$totalFreedMB += $size
Write-Host "     Freed ~${size} MB" -ForegroundColor Green

# --- 2. Windows Update Cache ---
Write-Host "[2/8] Clearing Windows Update cache..." -ForegroundColor Yellow
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
$size = Get-FolderSizeMB "C:\Windows\SoftwareDistribution\Download"
Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service wuauserv -ErrorAction SilentlyContinue
$totalFreedMB += $size
Write-Host "     Freed ~${size} MB" -ForegroundColor Green

# --- 3. CBS Logs ---
Write-Host "[3/8] Clearing CBS logs..." -ForegroundColor Yellow
$size = Get-FolderSizeMB "C:\Windows\Logs\CBS"
Remove-Item "C:\Windows\Logs\CBS\*" -Recurse -Force -ErrorAction SilentlyContinue
$totalFreedMB += $size
Write-Host "     Freed ~${size} MB" -ForegroundColor Green

# --- 4. Recycle Bin ---
Write-Host "[4/8] Emptying Recycle Bin..." -ForegroundColor Yellow
$shell = New-Object -ComObject Shell.Application
$recycleBin = $shell.Namespace(0xA)
$size = [math]::Round(($recycleBin.Items() | Measure-Object -Property Size -Sum).Sum / 1MB, 1)
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
$totalFreedMB += $size
Write-Host "     Freed ~${size} MB" -ForegroundColor Green

# --- 5. Browser Cache (Chrome & Edge) ---
Write-Host "[5/8] Clearing browser cache..." -ForegroundColor Yellow
$browserPaths = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"
)
$browserFreed = 0
foreach ($path in $browserPaths) {
    $s = Get-FolderSizeMB $path
    Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
    $browserFreed += $s
}
$totalFreedMB += $browserFreed
Write-Host "     Freed ~${browserFreed} MB from Chrome/Edge cache" -ForegroundColor Green

# --- 6. Teams Cache ---
Write-Host "[6/8] Clearing Microsoft Teams cache..." -ForegroundColor Yellow
$teamsPaths = @(
    "$env:APPDATA\Microsoft\Teams\Cache",
    "$env:APPDATA\Microsoft\Teams\blob_storage",
    "$env:APPDATA\Microsoft\Teams\databases",
    "$env:APPDATA\Microsoft\Teams\GPUCache",
    "$env:APPDATA\Microsoft\Teams\IndexedDB",
    "$env:APPDATA\Microsoft\Teams\Local Storage",
    "$env:APPDATA\Microsoft\Teams\tmp"
)
$teamsFreed = 0
foreach ($path in $teamsPaths) {
    $s = Get-FolderSizeMB $path
    Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
    $teamsFreed += $s
}
$totalFreedMB += $teamsFreed
Write-Host "     Freed ~${teamsFreed} MB from Teams cache" -ForegroundColor Green
if ($teamsFreed -gt 500) {
    $recommendations += "TEAMS CACHE: Cleared ${teamsFreed} MB from Teams cache — significant buildup. If Teams was running slow or crashing, this should help. Teams will rebuild its cache on next launch."
}

# --- 7. Windows Error Reporting ---
Write-Host "[7/8] Clearing Windows Error Reporting files..." -ForegroundColor Yellow
$werPaths = @(
    "C:\ProgramData\Microsoft\Windows\WER\ReportQueue",
    "C:\ProgramData\Microsoft\Windows\WER\ReportArchive",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER"
)
$werFreed = 0
foreach ($path in $werPaths) {
    $s = Get-FolderSizeMB $path
    Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
    $werFreed += $s
}
$totalFreedMB += $werFreed
Write-Host "     Freed ~${werFreed} MB from error reports" -ForegroundColor Green

# --- 8. Old System Restore Points ---
Write-Host "[8/8] Clean up old System Restore points?" -ForegroundColor Yellow
Write-Host "     This will keep only the most recent restore point." -ForegroundColor Gray
Write-Host "     Type 'run' to clean or 'skip' to skip." -ForegroundColor Gray
do {
    $srChoice = Read-Host "     Choice"
} while ($srChoice -ne "run" -and $srChoice -ne "skip")

if ($srChoice -eq "run") {
    $srSize = Get-FolderSizeMB "C:\System Volume Information"
    vssadmin delete shadows /for=C: /oldest /quiet 2>$null
    Write-Host "     Old restore points removed." -ForegroundColor Green
    $recommendations += "SYSTEM RESTORE: Old restore points cleared. A current restore point still exists. Consider creating a new one after cleanup: Checkpoint-Computer -Description 'Post-Cleanup' -RestorePointType MODIFY_SETTINGS"
} else {
    Write-Host "     Skipped." -ForegroundColor Gray
    $recommendations += "SYSTEM RESTORE: Skipped. If disk space is critically low, consider removing old restore points via System Properties > System Protection > Configure > Delete."
}

# --- Summary ---
$diskAfter = Get-PSDrive C
$freeAfter = [math]::Round($diskAfter.Free / 1GB, 2)
$actualFreed = [math]::Round($freeAfter - $freeBefore, 2)

Write-Host "`n--- Cleanup Summary ---" -ForegroundColor Cyan
Write-Host "     Before:      ${freeBefore} GB free" -ForegroundColor Gray
Write-Host "     After:       ${freeAfter} GB free" -ForegroundColor Green
Write-Host "     Total freed: ~${totalFreedMB} MB estimated / ${actualFreed} GB actual" -ForegroundColor Green

if ($freeAfter -lt 10) {
    $recommendations += "DISK STILL LOW: Even after cleanup, only ${freeAfter} GB is free. Consider uninstalling unused applications (Settings > Apps), moving large files to OneDrive, or upgrading storage."
} else {
    $recommendations += "DISK SPACE: ${freeAfter} GB free after cleanup. Disk space is now in a healthy range."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "STILL LOW|WARNING|critically") { "Red" } elseif ($rec -match "Skipped|Consider") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== Deep Disk Cleanup Complete ===" -ForegroundColor Cyan
