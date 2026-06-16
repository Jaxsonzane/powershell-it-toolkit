# ============================================================
#  ReinstallChrome.ps1 - Uninstall and Reinstall Chrome
#  Keeps user profile (bookmarks, passwords, extensions)
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== ReinstallChrome - Chrome Reinstall ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray
Write-Host "This will uninstall Chrome and reinstall the latest version." -ForegroundColor Yellow
Write-Host "Your bookmarks, passwords, and extensions will be kept." -ForegroundColor Green
Write-Host "`nType 'confirm' to proceed or 'exit' to cancel." -ForegroundColor Yellow
do { $choice = Read-Host "Choice" } while ($choice -ne "confirm" -and $choice -ne "exit")
if ($choice -eq "exit") { Write-Host "Cancelled." -ForegroundColor Gray; exit }

# ============================================================
# STEP 1 - Backup Profile Location
# ============================================================
Write-Host "`n[1/7] Locating Chrome profile data to preserve..." -ForegroundColor Yellow
$chromeProfilePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $chromeProfilePath) {
    $profileSizeMB = [math]::Round((Get-ChildItem $chromeProfilePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    Write-Host "     Profile found: $chromeProfilePath" -ForegroundColor Green
    Write-Host "     Profile size: ${profileSizeMB} MB — will be preserved." -ForegroundColor Green
} else {
    Write-Host "     No existing Chrome profile found. Fresh install will be performed." -ForegroundColor Gray
}

# ============================================================
# STEP 2 - Kill Chrome Processes
# ============================================================
Write-Host "`n[2/7] Killing Chrome processes..." -ForegroundColor Yellow
$chromeProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
if ($chromeProcs) {
    $chromeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "     Chrome processes killed." -ForegroundColor Green
} else {
    Write-Host "     Chrome is not running." -ForegroundColor Gray
}

# ============================================================
# STEP 3 - Uninstall Chrome (Keep Profile)
# ============================================================
Write-Host "`n[3/7] Uninstalling Chrome (keeping your profile)..." -ForegroundColor Yellow

# Try Chrome's built-in uninstaller first
$chromeUninstallers = @(
    "$env:ProgramFiles\Google\Chrome\Application\*\Installer\setup.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\*\Installer\setup.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\*\Installer\setup.exe"
)
$uninstallerFound = $false
foreach ($pattern in $chromeUninstallers) {
    $uninstaller = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uninstaller) {
        Write-Host "     Running Chrome uninstaller..." -ForegroundColor Gray
        Start-Process $uninstaller.FullName -ArgumentList "--uninstall --multi-install --chrome --force-uninstall" -Wait -ErrorAction SilentlyContinue
        Write-Host "     Chrome uninstalled." -ForegroundColor Green
        $uninstallerFound = $true
        break
    }
}

# Fallback - registry uninstall string
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
        if ($chromeReg -and $chromeReg.UninstallString) {
            $uninstallCmd = $chromeReg.UninstallString -replace '"',''
            Start-Process $uninstallCmd -ArgumentList "--force-uninstall" -Wait -ErrorAction SilentlyContinue
            Write-Host "     Chrome uninstalled via registry." -ForegroundColor Green
            $uninstallerFound = $true
            break
        }
    }
}

if (-not $uninstallerFound) {
    Write-Host "     Chrome uninstaller not found. Removing program files manually..." -ForegroundColor Yellow
}

# Remove Chrome program files only — NOT the User Data folder
$chromeProgramPaths = @(
    "$env:ProgramFiles\Google\Chrome",
    "$env:ProgramFiles(x86)\Google\Chrome"
)
foreach ($path in $chromeProgramPaths) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "     Removed: $path" -ForegroundColor Green
    }
}

# Remove Chrome registry keys
$regKeysToRemove = @(
    "HKLM:\SOFTWARE\Google\Chrome",
    "HKLM:\SOFTWARE\WOW6432Node\Google\Chrome",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome"
)
foreach ($key in $regKeysToRemove) {
    if (Test-Path $key) {
        Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "     Removed registry key: $key" -ForegroundColor Green
    }
}

Write-Host "     Chrome uninstalled. Profile data preserved at:" -ForegroundColor Green
Write-Host "     $chromeProfilePath" -ForegroundColor Gray
Start-Sleep -Seconds 3

# ============================================================
# STEP 4 - Download Latest Chrome Installer
# ============================================================
Write-Host "`n[4/7] Downloading latest Chrome installer..." -ForegroundColor Yellow
$installerPath = "$env:TEMP\ChromeSetup.exe"
$downloadUrl   = "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe"

try {
    Write-Host "     Downloading from Google..." -ForegroundColor Gray
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($downloadUrl, $installerPath)

    if (Test-Path $installerPath) {
        $sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
        Write-Host "     Downloaded: $installerPath (${sizeMB} MB)" -ForegroundColor Green
    } else {
        throw "File not found after download."
    }
} catch {
    Write-Host "     Download failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "     Trying alternate download method..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 120
        Write-Host "     Downloaded successfully." -ForegroundColor Green
    } catch {
        Write-Host "     ERROR: Could not download Chrome installer." -ForegroundColor Red
        Write-Host "     Please download manually from https://www.google.com/chrome and install." -ForegroundColor Yellow
        exit
    }
}

# ============================================================
# STEP 5 - Install Chrome Silently
# ============================================================
Write-Host "`n[5/7] Installing Chrome silently..." -ForegroundColor Yellow
try {
    $installProcess = Start-Process $installerPath -ArgumentList "/silent /install" -Wait -PassThru -ErrorAction Stop
    if ($installProcess.ExitCode -eq 0 -or $installProcess.ExitCode -eq 1) {
        Write-Host "     Chrome installed successfully." -ForegroundColor Green
    } else {
        Write-Host "     Installer exited with code: $($installProcess.ExitCode)" -ForegroundColor Yellow
        Write-Host "     Chrome may still have installed. Check below." -ForegroundColor Gray
    }
} catch {
    Write-Host "     ERROR during install: $($_.Exception.Message)" -ForegroundColor Red
}

# Clean up installer
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
Write-Host "     Installer cleaned up." -ForegroundColor Gray
Start-Sleep -Seconds 3

# ============================================================
# STEP 6 - Verify Installation
# ============================================================
Write-Host "`n[6/7] Verifying Chrome installation..." -ForegroundColor Yellow
$chromeExePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
)
$chromeExe = $chromeExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($chromeExe) {
    $newVersion = (Get-Item $chromeExe).VersionInfo.FileVersion
    Write-Host "     Chrome installed: $chromeExe" -ForegroundColor Green
    Write-Host "     Version: $newVersion" -ForegroundColor Green
} else {
    Write-Host "     WARNING: Chrome executable not found after install." -ForegroundColor Red
    Write-Host "     Try installing manually from https://www.google.com/chrome" -ForegroundColor Yellow
}

# Verify profile is still intact
if (Test-Path $chromeProfilePath) {
    Write-Host "     Profile data intact at: $chromeProfilePath" -ForegroundColor Green
} else {
    Write-Host "     WARNING: Profile data not found. Bookmarks/passwords may be missing." -ForegroundColor Red
}

# ============================================================
# STEP 7 - Launch Chrome
# ============================================================
Write-Host "`n[7/7] Launch Chrome now?" -ForegroundColor Yellow
Write-Host "     Type 'run' to launch or 'skip' to skip." -ForegroundColor Gray
do { $launchChoice = Read-Host "     Choice" } while ($launchChoice -ne "run" -and $launchChoice -ne "skip")

if ($launchChoice -eq "run" -and $chromeExe) {
    Start-Process $chromeExe
    Write-Host "     Chrome launched." -ForegroundColor Green
    Write-Host "     Your bookmarks, passwords, and extensions should be restored." -ForegroundColor Green
} else {
    Write-Host "     Skipped. Launch Chrome from the Start menu when ready." -ForegroundColor Gray
}

Write-Host "`n=== Chrome Reinstall Complete ===" -ForegroundColor Cyan
