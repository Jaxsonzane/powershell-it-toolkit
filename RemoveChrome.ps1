# ============================================================
#  RemoveChrome.ps1 - Complete Chrome Removal
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== RemoveChrome - Complete Google Chrome Removal ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

Write-Host "WARNING: This will completely remove Google Chrome and all user data." -ForegroundColor Red
Write-Host "Bookmarks, passwords, history, and extensions will be deleted." -ForegroundColor Red
Write-Host "Type 'confirm' to proceed or 'exit' to cancel." -ForegroundColor Yellow
do { $choice = Read-Host "Choice" } while ($choice -ne "confirm" -and $choice -ne "exit")
if ($choice -eq "exit") { Write-Host "Cancelled." -ForegroundColor Gray; exit }

# ============================================================
# STEP 1 - Kill Chrome Processes
# ============================================================
Write-Host "`n[1/6] Killing Chrome processes..." -ForegroundColor Yellow
$chromeProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
if ($chromeProcs) {
    $chromeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "     Chrome processes killed." -ForegroundColor Green
} else {
    Write-Host "     Chrome is not running." -ForegroundColor Gray
}

# ============================================================
# STEP 2 - Uninstall via Windows Installer
# ============================================================
Write-Host "`n[2/6] Uninstalling Chrome via Windows Installer..." -ForegroundColor Yellow

# Method 1 - uninstall via chrome's own uninstaller
$chromeUninstallers = @(
    "$env:ProgramFiles\Google\Chrome\Application\*\Installer\setup.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\*\Installer\setup.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\*\Installer\setup.exe"
)
$uninstallerFound = $false
foreach ($pattern in $chromeUninstallers) {
    $uninstaller = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uninstaller) {
        Write-Host "     Found uninstaller: $($uninstaller.FullName)" -ForegroundColor Gray
        Start-Process $uninstaller.FullName -ArgumentList "--uninstall --multi-install --chrome --force-uninstall" -Wait -ErrorAction SilentlyContinue
        Write-Host "     Chrome uninstaller ran." -ForegroundColor Green
        $uninstallerFound = $true
        break
    }
}

# Method 2 - uninstall via registry uninstall string
if (-not $uninstallerFound) {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($regPath in $regPaths) {
        $chromeReg = Get-ChildItem $regPath -ErrorAction SilentlyContinue |
            Get-ItemProperty | Where-Object { $_.DisplayName -match "Google Chrome" } |
            Select-Object -First 1
        if ($chromeReg) {
            Write-Host "     Found Chrome in registry: $($chromeReg.DisplayName)" -ForegroundColor Gray
            if ($chromeReg.UninstallString) {
                $uninstallCmd = $chromeReg.UninstallString -replace '"','' 
                Start-Process $uninstallCmd -ArgumentList "--force-uninstall" -Wait -ErrorAction SilentlyContinue
                Write-Host "     Uninstall command ran." -ForegroundColor Green
                $uninstallerFound = $true
                break
            }
        }
    }
}

# Method 3 - WMI uninstall
if (-not $uninstallerFound) {
    Write-Host "     Trying WMI uninstall..." -ForegroundColor Gray
    $wmiChrome = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Google Chrome" } | Select-Object -First 1
    if ($wmiChrome) {
        $wmiChrome.Uninstall() | Out-Null
        Write-Host "     WMI uninstall ran." -ForegroundColor Green
        $uninstallerFound = $true
    }
}

if (-not $uninstallerFound) {
    Write-Host "     Could not find Chrome uninstaller. Proceeding with manual file removal." -ForegroundColor Yellow
}

Start-Sleep -Seconds 3

# ============================================================
# STEP 3 - Remove Chrome Program Files
# ============================================================
Write-Host "`n[3/6] Removing Chrome program files..." -ForegroundColor Yellow
$chromeProgramPaths = @(
    "$env:ProgramFiles\Google\Chrome",
    "$env:ProgramFiles(x86)\Google\Chrome",
    "$env:LOCALAPPDATA\Google\Chrome"
)
foreach ($path in $chromeProgramPaths) {
    if (Test-Path $path) {
        $sizeMB = [math]::Round((Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $path)) {
            Write-Host "     Removed: $path (~${sizeMB} MB)" -ForegroundColor Green
        } else {
            Write-Host "     Could not fully remove: $path" -ForegroundColor Yellow
        }
    }
}

# Remove Google Update for Chrome
$googleUpdatePaths = @(
    "$env:ProgramFiles\Google\Update",
    "$env:ProgramFiles(x86)\Google\Update",
    "$env:LOCALAPPDATA\Google\Update"
)
foreach ($path in $googleUpdatePaths) {
    if (Test-Path $path) {
        # Stop Google Update service first
        Get-Service -Name "gupdate","gupdatem" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
        Get-Service -Name "gupdate","gupdatem" -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "     Removed Google Update: $path" -ForegroundColor Green
    }
}

# Clean up empty Google folder
@("$env:ProgramFiles\Google", "$env:ProgramFiles(x86)\Google") | ForEach-Object {
    if ((Test-Path $_) -and -not (Get-ChildItem $_ -ErrorAction SilentlyContinue)) {
        Remove-Item $_ -Force -ErrorAction SilentlyContinue
        Write-Host "     Removed empty Google folder: $_" -ForegroundColor Green
    }
}

# ============================================================
# STEP 4 - Remove User Profile Data
# ============================================================
Write-Host "`n[4/6] Remove Chrome user profile data?" -ForegroundColor Yellow
Write-Host "     This deletes bookmarks, passwords, history, and extensions." -ForegroundColor Gray
Write-Host "     Type 'run' to delete or 'skip' to keep user data." -ForegroundColor Gray
do { $profileChoice = Read-Host "     Choice" } while ($profileChoice -ne "run" -and $profileChoice -ne "skip")

if ($profileChoice -eq "run") {
    $chromeUserPaths = @(
        "$env:LOCALAPPDATA\Google\Chrome",
        "$env:APPDATA\Google\Chrome",
        "$env:LOCALAPPDATA\Google\CrashReports"
    )
    foreach ($path in $chromeUserPaths) {
        if (Test-Path $path) {
            $sizeMB = [math]::Round((Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "     Removed user data: $path (~${sizeMB} MB)" -ForegroundColor Green
        }
    }
} else {
    Write-Host "     Skipped. User profile data kept." -ForegroundColor Gray
}

# ============================================================
# STEP 5 - Clean Registry
# ============================================================
Write-Host "`n[5/6] Cleaning Chrome registry entries..." -ForegroundColor Yellow
$regKeysToRemove = @(
    "HKLM:\SOFTWARE\Google\Chrome",
    "HKLM:\SOFTWARE\WOW6432Node\Google\Chrome",
    "HKCU:\SOFTWARE\Google\Chrome",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome",
    "HKLM:\SOFTWARE\Policies\Google\Chrome",
    "HKCU:\SOFTWARE\Policies\Google\Chrome"
)
foreach ($key in $regKeysToRemove) {
    if (Test-Path $key) {
        Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "     Removed registry key: $key" -ForegroundColor Green
    }
}

# Remove Google Update registry entries
$googleUpdateRegKeys = @(
    "HKLM:\SOFTWARE\Google\Update",
    "HKLM:\SOFTWARE\WOW6432Node\Google\Update",
    "HKCU:\SOFTWARE\Google\Update"
)
foreach ($key in $googleUpdateRegKeys) {
    if (Test-Path $key) {
        Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "     Removed Google Update registry key: $key" -ForegroundColor Green
    }
}

# Remove Google Update scheduled tasks
Get-ScheduledTask -TaskName "GoogleUpdate*" -ErrorAction SilentlyContinue | ForEach-Object {
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "     Removed scheduled task: $($_.TaskName)" -ForegroundColor Green
}

# ============================================================
# STEP 6 - Verify Removal
# ============================================================
Write-Host "`n[6/6] Verifying Chrome removal..." -ForegroundColor Yellow

$chromeStillExists = $false

# Check for executable
$chromeExePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
foreach ($exePath in $chromeExePaths) {
    if (Test-Path $exePath) {
        Write-Host "     WARNING: Chrome executable still found at: $exePath" -ForegroundColor Red
        $chromeStillExists = $true
    }
}

# Check registry
$chromeRegCheck = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
    Get-ItemProperty | Where-Object { $_.DisplayName -match "Google Chrome" }
if ($chromeRegCheck) {
    Write-Host "     WARNING: Chrome still found in uninstall registry." -ForegroundColor Yellow
    $chromeStillExists = $true
}

if (-not $chromeStillExists) {
    Write-Host "     Chrome has been completely removed." -ForegroundColor Green
} else {
    Write-Host "     Some Chrome components may remain. A reboot may be required to complete removal." -ForegroundColor Yellow
}

Write-Host "`n=== Chrome Removal Complete ===" -ForegroundColor Cyan
Write-Host "A reboot is recommended to complete the removal." -ForegroundColor Yellow
