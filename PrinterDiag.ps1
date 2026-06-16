# ============================================================
#  PrinterDiag.ps1 - Printer Diagnostic
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== PrinterDiag - Printer Diagnostic ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()

# --- 1. Print Spooler Status ---
Write-Host "[1/5] Checking Print Spooler service..." -ForegroundColor Yellow
$spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
if ($spooler.Status -eq "Running") {
    Write-Host "     Spooler: Running" -ForegroundColor Green
    $recommendations += "SPOOLER: Print Spooler is running normally."
} else {
    Write-Host "     WARNING: Print Spooler is $($spooler.Status)!" -ForegroundColor Red
    $recommendations += "SPOOLER: Print Spooler is not running (Status: $($spooler.Status)). Run PrintSpoolerReset.ps1 to fix this."
}

# --- 2. List Installed Printers ---
Write-Host "`n[2/5] Installed printers..." -ForegroundColor Yellow
$printers = Get-Printer -ErrorAction SilentlyContinue
if ($printers) {
    foreach ($p in $printers) {
        $color = if ($p.PrinterStatus -eq "Normal") { "Green" } else { "Red" }
        Write-Host "     Name: $($p.Name)" -ForegroundColor $color
        Write-Host "     Status: $($p.PrinterStatus) | Default: $($p.Default) | Shared: $($p.Shared)" -ForegroundColor Gray
        Write-Host "     Port: $($p.PortName)`n" -ForegroundColor Gray

        if ($p.PrinterStatus -ne "Normal") {
            $recommendations += "PRINTER OFFLINE: '$($p.Name)' has status '$($p.PrinterStatus)'. Check the printer is powered on, connected, and the port $($p.PortName) is reachable. Run PrintSpoolerReset.ps1 if the status is stuck."
        }
    }
} else {
    Write-Host "     No printers found." -ForegroundColor Red
    $recommendations += "NO PRINTERS: No printers are installed on this machine. Add a printer via Settings > Bluetooth & Devices > Printers & Scanners."
}

# --- 3. Check Print Queue ---
Write-Host "[3/5] Checking print queue for stuck jobs..." -ForegroundColor Yellow
$allJobs = @()
Get-Printer | ForEach-Object {
    $jobs = Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue
    if ($jobs) { $allJobs += $jobs }
}
if ($allJobs) {
    Write-Host "     Stuck jobs found:" -ForegroundColor Red
    foreach ($j in $allJobs) {
        Write-Host "     Job ID: $($j.ID) | Document: $($j.DocumentName) | Status: $($j.JobStatus)" -ForegroundColor Red
    }
    $recommendations += "STUCK JOBS: $($allJobs.Count) stuck print job(s) found. Run PrintSpoolerReset.ps1 to clear the queue, or manually delete jobs in Settings > Printers."
} else {
    Write-Host "     No stuck print jobs found." -ForegroundColor Green
    $recommendations += "PRINT QUEUE: No stuck jobs detected. Queue is clear."
}

# --- 4. Test Printer Port Connectivity ---
Write-Host "`n[4/5] Testing printer port connectivity..." -ForegroundColor Yellow
$ports = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\d+\.\d+\.\d+\.\d+" }
if ($ports) {
    foreach ($port in $ports) {
        $ping = Test-Connection -ComputerName $port.PrinterHostAddress -Count 2 -ErrorAction SilentlyContinue
        if ($ping) {
            Write-Host "     Port: $($port.Name) | IP: $($port.PrinterHostAddress) | Reachable: YES" -ForegroundColor Green
        } else {
            Write-Host "     Port: $($port.Name) | IP: $($port.PrinterHostAddress) | Reachable: NO" -ForegroundColor Red
            $recommendations += "PRINTER UNREACHABLE: Printer at IP $($port.PrinterHostAddress) (Port: $($port.Name)) is not responding to ping. Check if the printer is powered on and connected to the network. Verify the IP address hasn't changed — if it has, update the port in Printer Properties > Ports."
        }
    }
} else {
    Write-Host "     No network printer ports found (may be USB only)." -ForegroundColor Gray
    $recommendations += "PRINTER PORTS: No network printer ports detected. Printers on this machine appear to be USB-connected."
}

# --- 5. Driver Check ---
Write-Host "`n[5/5] Installed printer drivers..." -ForegroundColor Yellow
$drivers = Get-PrinterDriver -ErrorAction SilentlyContinue
if ($drivers) {
    foreach ($d in $drivers) {
        Write-Host "     $($d.Name) — $($d.PrinterEnvironment)" -ForegroundColor Gray
    }
    $recommendations += "DRIVERS: $($drivers.Count) printer driver(s) installed. If a printer is showing errors, try removing and reinstalling its driver via Print Management or Device Manager."
} else {
    Write-Host "     No printer drivers found." -ForegroundColor Red
    $recommendations += "DRIVERS: No printer drivers found. This may explain why printers aren't working. Reinstall the printer and its drivers from the manufacturer's website."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "WARNING|OFFLINE|STUCK|UNREACHABLE|No printers|No printer drivers") { "Red" } elseif ($rec -match "USB|may be") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== Printer Diagnostic Complete ===" -ForegroundColor Cyan
