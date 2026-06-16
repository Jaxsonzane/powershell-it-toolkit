# ============================================================
#  SpeedBoost.ps1 - Quick PC Performance Cleanup
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== SpeedBoost - PC Cleanup Script ===" -ForegroundColor Cyan
Write-Host "Running as: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()

# --- 1. Clear Temp Files ---
Write-Host "[1/6] Clearing temp files..." -ForegroundColor Yellow
$tempBefore = (Get-ChildItem "$env:TEMP" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
$tempAfter = (Get-ChildItem "$env:TEMP" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$tempFreedMB = [math]::Round(($tempBefore - $tempAfter) / 1MB, 1)
Write-Host "     Done. Freed approximately ${tempFreedMB} MB." -ForegroundColor Green

if ($tempFreedMB -gt 500) {
    $recommendations += "TEMP FILES: Cleared ${tempFreedMB} MB of temp files — significant buildup detected. Consider scheduling regular cleanups or running Disk Cleanup (cleanmgr) to also clear Windows Update cache and system files."
} else {
    $recommendations += "TEMP FILES: Cleared ${tempFreedMB} MB of temp files. Temp folders were reasonably clean."
}

# --- 2. Flush DNS Cache ---
Write-Host "[2/6] Flushing DNS cache..." -ForegroundColor Yellow
ipconfig /flushdns | Out-Null
Write-Host "     Done." -ForegroundColor Green
$recommendations += "DNS: Cache flushed successfully. If users report specific sites not loading after this, it may indicate a DNS server issue — run NetDiag.ps1 to investigate further."

# --- 3. Set Power Plan to High Performance ---
Write-Host "[3/6] Setting power plan to High Performance..." -ForegroundColor Yellow
$result = powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "     Done." -ForegroundColor Green
    $recommendations += "POWER PLAN: Set to High Performance. This prevents CPU throttling. Note: on a laptop this will reduce battery life — switch back to Balanced when on battery using: powercfg /setactive SCHEME_BALANCED."
} else {
    Write-Host "     WARNING: Could not set power plan. May already be on a custom plan." -ForegroundColor Yellow
    $recommendations += "POWER PLAN: Could not switch to High Performance — the machine may be using a custom power plan. Manually verify in Control Panel > Power Options and ensure the CPU is not being throttled."
}

# --- 4. Check Disk Space ---
Write-Host "[4/6] Checking C: drive space..." -ForegroundColor Yellow
$disk    = Get-PSDrive C
$usedGB  = [math]::Round($disk.Used / 1GB, 1)
$freeGB  = [math]::Round($disk.Free / 1GB, 1)
$totalGB = [math]::Round(($disk.Used + $disk.Free) / 1GB, 1)
$freePct = [math]::Round(($freeGB / $totalGB) * 100, 0)

Write-Host "     Used: ${usedGB} GB  |  Free: ${freeGB} GB  |  Total: ${totalGB} GB  |  Free: ${freePct}%" -ForegroundColor $(if ($freeGB -lt 10) { "Red" } elseif ($freeGB -lt 20) { "Yellow" } else { "Green" })

if ($freeGB -lt 10) {
    Write-Host "     WARNING: Critically low disk space!" -ForegroundColor Red
    $recommendations += "DISK SPACE CRITICAL: Only ${freeGB} GB free (${freePct}% of ${totalGB} GB). This will cause serious performance issues and may prevent Windows Update from running. Immediately run Disk Cleanup (cleanmgr /sagerun:1), uninstall unused programs, and check for large files using WinDirStat or TreeSize."
} elseif ($freeGB -lt 20) {
    Write-Host "     WARNING: Disk space getting low." -ForegroundColor Yellow
    $recommendations += "DISK SPACE LOW: ${freeGB} GB free (${freePct}% of ${totalGB} GB). Getting low — run Disk Cleanup and review large files before it becomes critical. Target: keep at least 15-20% free."
} else {
    $recommendations += "DISK SPACE: ${freeGB} GB free (${freePct}% of ${totalGB} GB). Disk space looks healthy. No action needed."
}

# --- 5. Show Top 5 CPU-Hungry Processes ---
Write-Host "[5/6] Top 5 processes by CPU..." -ForegroundColor Yellow
$topProcs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
$topProcs | ForEach-Object {
    Write-Host ("     {0,-30} CPU: {1}  RAM: {2} MB" -f $_.Name, $_.CPU, [math]::Round($_.WorkingSet/1MB, 1)) -ForegroundColor Gray
}

$highCpuProcs = $topProcs | Where-Object { $_.CPU -gt 60 }
$highRamProcs = $topProcs | Where-Object { ($_.WorkingSet/1MB) -gt 500 }

if ($highCpuProcs) {
    foreach ($p in $highCpuProcs) {
        $recommendations += "HIGH CPU: Process '$($p.Name)' has accumulated high CPU time ($($p.CPU)s). If the machine feels slow right now, check if this process is actively spiking in Task Manager. If it's antivirus, wait for it to finish. If it's unknown, investigate further."
    }
} else {
    $recommendations += "CPU: No runaway processes detected in the top 5. CPU usage looks normal."
}

if ($highRamProcs) {
    foreach ($p in $highRamProcs) {
        $recommendations += "HIGH RAM: Process '$($p.Name)' is using $([math]::Round($p.WorkingSet/1MB, 1)) MB of RAM. If total RAM usage is high, consider restarting this process or rebooting the machine."
    }
}

# --- 6. SFC Scan (optional) ---
Write-Host "[6/6] System File Check (sfc /scannow)..." -ForegroundColor Yellow
Write-Host "     This may take 5-10 minutes. Type 'run' to start or 'skip' to skip." -ForegroundColor Gray
do {
    $choice = Read-Host "     Choice"
} while ($choice -ne "run" -and $choice -ne "skip")

if ($choice -eq "run") {
    sfc /scannow
    if ($LASTEXITCODE -eq 0) {
        $recommendations += "SFC SCAN: System File Checker completed. If it found and repaired files, a reboot is required to finalize repairs. If it found unfixable files, run: DISM /Online /Cleanup-Image /RestoreHealth and then run sfc /scannow again."
    } else {
        $recommendations += "SFC SCAN: System File Checker returned an error. Try running: DISM /Online /Cleanup-Image /RestoreHealth first, then re-run sfc /scannow."
    }
} else {
    $recommendations += "SFC SCAN: Skipped. If the machine has recurring crashes, errors, or unexplained slowness, run sfc /scannow manually as a next step to check for corrupted system files."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "CRITICAL|WARNING|HIGH CPU|HIGH RAM") { "Red" } elseif ($rec -match "LOW|Skipped|could not|custom plan") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

# --- Done ---
Write-Host "=== All done! Consider rebooting for full effect. ===" -ForegroundColor Cyan
