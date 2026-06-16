# ============================================================
#  UserProfileDiag.ps1 - User Profile Diagnostic
#  Run as Administrator in PowerShell
# ============================================================

Write-Host "`n=== UserProfileDiag - User Profile Diagnostic ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

$recommendations = @()

# --- 1. List All User Profiles ---
Write-Host "[1/5] Scanning user profiles on this machine..." -ForegroundColor Yellow
$profiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { -not $_.Special }
foreach ($p in $profiles) {
    $sizeMB = if (Test-Path $p.LocalPath) {
        [math]::Round((Get-ChildItem $p.LocalPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    } else { 0 }
    $color = if ($p.Status -ne 0) { "Red" } else { "Green" }
    Write-Host "     Path: $($p.LocalPath)" -ForegroundColor $color
    Write-Host "     Status: $($p.Status) | Loaded: $($p.Loaded) | Size: ${sizeMB} MB`n" -ForegroundColor Gray

    if ($p.Status -ne 0) {
        $recommendations += "CORRUPT PROFILE: Profile at '$($p.LocalPath)' has a non-zero status ($($p.Status)) which indicates corruption. Back up the user's data and create a new profile — see next steps below."
    }
    if ($sizeMB -gt 5000) {
        $recommendations += "LARGE PROFILE: Profile at '$($p.LocalPath)' is ${sizeMB} MB. Large profiles slow down login times significantly. Check for large files in Documents, Downloads, and AppData. Consider redirecting folders to OneDrive."
    }
}

# --- 2. Check for Temp Profile Signs ---
Write-Host "[2/5] Checking for temporary profile indicators..." -ForegroundColor Yellow
$tempProfiles = Get-ChildItem "C:\Users" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "TEMP" -or $_.Name -match "\.bak" }
if ($tempProfiles) {
    foreach ($t in $tempProfiles) {
        Write-Host "     WARNING: Temp/backup profile found: $($t.FullName)" -ForegroundColor Red
    }
    $recommendations += "TEMP PROFILE DETECTED: One or more temp or .bak profile folders found under C:\Users. This means Windows couldn't load the real profile and created a temporary one. The user will lose settings/desktop items on each login. Fix: check the registry at HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList for duplicate SIDs and remove the .bak entry."
} else {
    Write-Host "     No temp profiles detected." -ForegroundColor Green
    $recommendations += "TEMP PROFILES: No temporary or backup profiles detected. Profile folder looks clean."
}

# --- 3. Check ProfileList Registry ---
Write-Host "`n[3/5] Checking ProfileList registry for duplicate SIDs..." -ForegroundColor Yellow
$profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$regProfiles = Get-ChildItem $profileListPath -ErrorAction SilentlyContinue
$duplicates = $regProfiles | Group-Object { ($_ | Get-ItemProperty).ProfileImagePath } | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    foreach ($d in $duplicates) {
        Write-Host "     WARNING: Duplicate SID entries for: $($d.Name)" -ForegroundColor Red
    }
    $recommendations += "DUPLICATE SID: Duplicate ProfileList registry entries detected for: $($duplicates.Name -join ', '). This causes Windows to load a temp profile. Fix: open regedit > HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList, find the SID with .bak suffix, delete it, and rename the clean SID entry by removing .bak."
} else {
    Write-Host "     No duplicate SIDs found." -ForegroundColor Green
    $recommendations += "REGISTRY: No duplicate SID entries found in ProfileList. Registry looks clean."
}

# --- 4. Check AppData Folder ---
Write-Host "`n[4/5] Checking AppData for common problem folders..." -ForegroundColor Yellow
$appDataPath = "C:\Users\$env:USERNAME\AppData"
if (Test-Path $appDataPath) {
    $localSize  = [math]::Round((Get-ChildItem "$appDataPath\Local" -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
    $roamSize   = [math]::Round((Get-ChildItem "$appDataPath\Roaming" -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host "     AppData\Local size:   ${localSize} MB" -ForegroundColor $(if ($localSize -gt 5000) { "Red" } else { "Gray" })
    Write-Host "     AppData\Roaming size: ${roamSize} MB" -ForegroundColor $(if ($roamSize -gt 2000) { "Red" } else { "Gray" })

    if ($localSize -gt 5000) {
        $recommendations += "APPDATA LOCAL: AppData\Local is ${localSize} MB — unusually large. Common culprits: browser cache, Teams cache, Outlook cache. Clear via: %LocalAppData%\Microsoft\Teams\Cache and %LocalAppData%\Google\Chrome\User Data\Default\Cache."
    }
    if ($roamSize -gt 2000) {
        $recommendations += "APPDATA ROAMING: AppData\Roaming is ${roamSize} MB — larger than expected. This can slow down login if roaming profiles are in use. Review large folders inside."
    }
    if ($localSize -le 5000 -and $roamSize -le 2000) {
        $recommendations += "APPDATA: AppData sizes look normal (Local: ${localSize} MB, Roaming: ${roamSize} MB)."
    }
}

# --- 5. Recent Login Events ---
Write-Host "`n[5/5] Recent login events (last 5)..." -ForegroundColor Yellow
$loginEvents = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624} -MaxEvents 5 -ErrorAction SilentlyContinue
if ($loginEvents) {
    foreach ($e in $loginEvents) {
        Write-Host "     $($e.TimeCreated) — $($e.Message.Split("`n")[0])" -ForegroundColor Gray
    }
    $recommendations += "LOGIN EVENTS: Recent login events found. If a user reports losing their profile repeatedly, check Security Event Log (Event ID 4624) for patterns in login failures or temp profile loads."
} else {
    Write-Host "     Could not retrieve login events (may need audit policy enabled)." -ForegroundColor Yellow
    $recommendations += "LOGIN EVENTS: Could not read login events. Enable audit logon events via: gpedit.msc > Computer Configuration > Windows Settings > Security Settings > Local Policies > Audit Policy."
}

# --- Recommended Actions ---
Write-Host "`n=== Recommended Actions ===" -ForegroundColor Cyan
$i = 1
foreach ($rec in $recommendations) {
    $color = if ($rec -match "CORRUPT|TEMP PROFILE|DUPLICATE|WARNING") { "Red" } elseif ($rec -match "LARGE|Could not|unusually") { "Yellow" } else { "Green" }
    Write-Host "  $i. $rec`n" -ForegroundColor $color
    $i++
}

Write-Host "=== User Profile Diagnostic Complete ===" -ForegroundColor Cyan
