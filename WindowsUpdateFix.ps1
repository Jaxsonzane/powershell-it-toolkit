# ============================================================
#  WindowsUpdateFix.ps1 - Windows Update Reset & Repair
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== WindowsUpdateFix - Windows Update Reset ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()

Write-Host "WARNING: This will stop Windows Update services and clear the update cache." -ForegroundColor Red
Write-Host "Type 'confirm' to proceed or 'exit' to cancel." -ForegroundColor Yellow
do {
    $choice = Read-Host "Choice"
} while ($choice -ne "confirm" -and $choice -ne "exit")

if ($choice -eq "exit") {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit
}

# --- 1. Stop Update Services ---
Write-Host "`n[1/6] Stopping Windows Update services..." -ForegroundColor Yellow
$services = @("wuauserv", "cryptSvc", "bits", "msiserver")
foreach ($svc in $services) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Write-Host "     Stopped: $svc" -ForegroundColor Gray
}
Write-Host "     Done." -ForegroundColor Green

# --- 2. Clear Update Cache ---
Write-Host "[2/6] Clearing Windows Update cache..." -ForegroundColor Yellow
$cachePath = "C:\Windows\SoftwareDistribution"
$catroot   = "C:\Windows\System32\catroot2"
$sizeBefore = [math]::Round((Get-ChildItem $cachePath -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)

Remove-Item "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$catroot\*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "     Cleared approximately ${sizeBefore} MB from update cache." -ForegroundColor Green
$recommendations += "UPDATE CACHE: Cleared ${sizeBefore} MB from SoftwareDistribution folder. Windows will re-download update metadata on next check — this is normal."

# --- 3. Reset Winsock & Network (Update relies on it) ---
Write-Host "[3/6] Resetting network components..." -ForegroundColor Yellow
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
Write-Host "     Done." -ForegroundColor Green

# --- 4. Re-register Update DLLs ---
Write-Host "[4/6] Re-registering Windows Update DLLs..." -ForegroundColor Yellow
$dlls = @(
    "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll",
    "browseui.dll", "jscript.dll", "vbscript.dll", "scrrun.dll",
    "msxml.dll", "msxml3.dll", "msxml6.dll", "actxprxy.dll",
    "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll",
    "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll",
    "oleaut32.dll", "ole32.dll", "shell32.dll", "wuapi.dll",
    "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll",
    "wups2.dll", "wuweb.dll", "qmgr.dll", "qmgrprxy.dll",
    "wucltux.dll", "muweb.dll", "wuwebv.dll"
)
foreach ($dll in $dlls) {
    regsvr32.exe /s $dll 2>$null
}
Write-Host "     Done." -ForegroundColor Green
$recommendations += "DLL REGISTRATION: Windows Update DLLs re-registered. This fixes 'Windows Update cannot currently check for updates' errors."

# --- 5. Restart Update Services ---
Write-Host "[5/6] Restarting Windows Update services..." -ForegroundColor Yellow
foreach ($svc in $services) {
    Start-Service -Name $svc -ErrorAction SilentlyContinue
    $s = Get-Service -Name $svc
    $color = if ($s.Status -eq "Running") { "Green" } else { "Red" }
    Write-Host "     $svc : $($s.Status)" -ForegroundColor $color
    if ($s.Status -ne "Running") {
        $recommendations += "SERVICE FAILED: '$svc' could not be restarted. Check Event Viewer > Windows Logs > System for errors related to this service."
    }
}

# --- 6. Check Last Update Status ---
Write-Host "`n[6/6] Checking last Windows Update status..." -ForegroundColor Yellow
$updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction SilentlyContinue
$updateSearcher = $updateSession.CreateUpdateSearcher()
$historyCount = $updateSearcher.GetTotalHistoryCount()
if ($historyCount -gt 0) {
    $lastUpdate = $updateSearcher.QueryHistory(0, 1) | Select-Object -First 1
    $resultCode = switch ($lastUpdate.ResultCode) {
        1 { "In Progress" }
        2 { "Succeeded" }
        3 { "Succeeded with Errors" }
        4 { "Failed" }
        5 { "Aborted" }
        default { "Unknown" }
    }
    Write-Host "     Last update: $($lastUpdate.Title)" -ForegroundColor Gray
    Write-Host "     Date: $($lastUpdate.Date) | Result: $resultCode" -ForegroundColor $(if ($resultCode -eq "Failed" -or $resultCode -eq "Aborted") { "Red" } else { "Green" })

    if ($resultCode -eq "Failed" -or $resultCode -eq "Aborted") {
        $recommendations += "LAST UPDATE FAILED: The last Windows Update '$($lastUpdate.Title)' failed or was aborted. After rebooting, go to Settings > Windows Update > View Update History to see the error code, then search Microsoft's support site for that specific error code."
    } else {
        $recommendations += "LAST UPDATE: Last update '$($lastUpdate.Title)' completed with status: $resultCode. Run Windows Update manually after rebooting to check for new updates."
    }
} else {
    Write-Host "     No update history found." -ForegroundColor Yellow
    $recommendations += "UPDATE HISTORY: No update history found. This may indicate updates have never run or history was cleared. Go to Settings > Windows Update and trigger a manual check."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "FAILED|ERROR|WARNING") { "Red" } elseif ($rec -match "No update|may indicate") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== Windows Update Fix Complete. Reboot recommended. ===" -ForegroundColor Cyan
