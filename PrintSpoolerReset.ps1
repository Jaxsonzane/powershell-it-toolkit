# ============================================================
#  PrintSpoolerReset.ps1 - Print Spooler Reset & Queue Clear
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== PrintSpoolerReset - Spooler Reset & Queue Clear ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()

Write-Host "WARNING: This will clear all pending print jobs." -ForegroundColor Red
Write-Host "Type 'confirm' to proceed or 'exit' to cancel." -ForegroundColor Yellow
do {
    $choice = Read-Host "Choice"
} while ($choice -ne "confirm" -and $choice -ne "exit")

if ($choice -eq "exit") {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit
}

# --- 1. Stop Spooler ---
Write-Host "`n[1/5] Stopping Print Spooler..." -ForegroundColor Yellow
Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$status = (Get-Service -Name Spooler).Status
if ($status -eq "Stopped") {
    Write-Host "     Spooler stopped." -ForegroundColor Green
} else {
    Write-Host "     WARNING: Could not stop spooler (Status: $status). Try rebooting." -ForegroundColor Red
    $recommendations += "SPOOLER STOP FAILED: Could not stop the Print Spooler service. Try rebooting the machine and running this script again, or manually stop it in services.msc."
}

# --- 2. Clear Print Queue ---
Write-Host "[2/5] Clearing print queue..." -ForegroundColor Yellow
$spoolPath = "C:\Windows\System32\spool\PRINTERS"
$files = Get-ChildItem $spoolPath -ErrorAction SilentlyContinue
if ($files) {
    Remove-Item "$spoolPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "     Cleared $($files.Count) file(s) from queue." -ForegroundColor Green
    $recommendations += "QUEUE CLEARED: Removed $($files.Count) stuck job file(s) from the spool folder."
} else {
    Write-Host "     Queue already empty." -ForegroundColor Green
    $recommendations += "QUEUE: Print queue was already empty. The issue may not be stuck jobs — check printer connectivity instead."
}

# --- 3. Restart Spooler ---
Write-Host "[3/5] Starting Print Spooler..." -ForegroundColor Yellow
Start-Service -Name Spooler -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$status = (Get-Service -Name Spooler).Status
if ($status -eq "Running") {
    Write-Host "     Spooler started successfully." -ForegroundColor Green
    $recommendations += "SPOOLER: Print Spooler restarted successfully."
} else {
    Write-Host "     WARNING: Spooler failed to start (Status: $status)." -ForegroundColor Red
    $recommendations += "SPOOLER START FAILED: Spooler could not restart. Check Event Viewer > Windows Logs > System for spooler errors, or run sfc /scannow to check for corrupted system files."
}

# --- 4. Set Spooler to Auto Start ---
Write-Host "[4/5] Ensuring Spooler is set to start automatically..." -ForegroundColor Yellow
Set-Service -Name Spooler -StartupType Automatic -ErrorAction SilentlyContinue
Write-Host "     Done." -ForegroundColor Green
$recommendations += "SPOOLER STARTUP: Spooler startup type set to Automatic — it will start on next reboot."

# --- 5. Verify Printers Still Visible ---
Write-Host "[5/5] Verifying printers are still visible..." -ForegroundColor Yellow
$printers = Get-Printer -ErrorAction SilentlyContinue
if ($printers) {
    foreach ($p in $printers) {
        Write-Host "     $($p.Name) | Status: $($p.PrinterStatus)" -ForegroundColor Gray
    }
    $recommendations += "PRINTERS: $($printers.Count) printer(s) still visible after reset. Try printing a test page — right-click the printer in Settings > Printers & Scanners > Printer Properties > Print Test Page."
} else {
    Write-Host "     WARNING: No printers visible after reset." -ForegroundColor Red
    $recommendations += "PRINTERS MISSING: No printers are visible after the reset. The drivers may need to be reinstalled. Go to Settings > Printers & Scanners and add the printer again."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "FAILED|WARNING|MISSING") { "Red" } elseif ($rec -match "empty|already") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== Print Spooler Reset Complete ===" -ForegroundColor Cyan
