# ============================================================
#  GALManager.ps1 - Global Address List Hide/Show Manager
#  Run as Administrator in PowerShell
#  Requires: Exchange Online PowerShell Module
# ============================================================

Write-Host "`n=== GALManager - Global Address List Manager ===" -ForegroundColor Cyan
Write-Host "Run by: $env:USERNAME | $(Get-Date)`n" -ForegroundColor Gray

# ============================================================
# STEP 1 - Check Exchange Online Connection
# ============================================================
Write-Host "[1/3] Checking Exchange Online connection..." -ForegroundColor Yellow
$connected = $false
try {
    $test = Get-Mailbox -ResultSize 1 -ErrorAction Stop | Out-Null
    $connected = $true
    Write-Host "     Already connected to Exchange Online." -ForegroundColor Green
} catch {
    Write-Host "     Not connected. Attempting to connect..." -ForegroundColor Yellow
    try {
        # Check if EXO module is installed
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            Write-Host "     Exchange Online Management module not found. Installing..." -ForegroundColor Yellow
            Install-Module -Name ExchangeOnlineManagement -Force -Scope CurrentUser
        }
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Connect-ExchangeOnline -UserPrincipalName "YOUR_ADMIN@yourdomain.com" -ShowProgress $true
        $connected = $true
        Write-Host "     Connected to Exchange Online." -ForegroundColor Green
    } catch {
        Write-Host "     ERROR: Could not connect to Exchange Online." -ForegroundColor Red
        Write-Host "     Make sure you have the ExchangeOnlineManagement module installed and valid credentials." -ForegroundColor Yellow
        Write-Host "     Install manually with: Install-Module -Name ExchangeOnlineManagement" -ForegroundColor Gray
        exit
    }
}

# ============================================================
# STEP 2 - Choose Action
# ============================================================
Write-Host "`n[2/3] What would you like to do?" -ForegroundColor Yellow
Write-Host "     'hide'   - Hide a user from the GAL" -ForegroundColor Gray
Write-Host "     'show'   - Show a user in the GAL (unhide)" -ForegroundColor Gray
Write-Host "     'check'  - Check a user's current GAL status" -ForegroundColor Gray
Write-Host "     'bulk'   - Hide or show multiple users from a list" -ForegroundColor Gray
Write-Host "     'report' - Show all users currently hidden from GAL" -ForegroundColor Gray
Write-Host "     'add'    - Add/update a user's GAL contact details" -ForegroundColor Gray
Write-Host "     'exit'   - Quit" -ForegroundColor Gray

do {
    $action = Read-Host "`n     Choice"
} while ($action -notin @("hide", "show", "check", "bulk", "report", "add", "exit"))

if ($action -eq "exit") {
    Write-Host "Exiting." -ForegroundColor Gray
    exit
}

# ============================================================
# STEP 3 - Execute Action
# ============================================================
Write-Host "`n[3/3] Running action: $action..." -ForegroundColor Yellow

# --- HIDE ---
if ($action -eq "hide") {
    $user = Read-Host "     Enter user email (e.g. jsmith@yourdomain.com)"
    try {
        $mailbox = Get-Mailbox -Identity $user -ErrorAction Stop
        $currentStatus = $mailbox.HiddenFromAddressListsEnabled

        if ($currentStatus -eq $true) {
            Write-Host "     '$user' is already hidden from the GAL." -ForegroundColor Yellow
        } else {
            Set-Mailbox -Identity $user -HiddenFromAddressListsEnabled $true -ErrorAction Stop
            $verify = Get-Mailbox -Identity $user | Select-Object -ExpandProperty HiddenFromAddressListsEnabled
            if ($verify -eq $true) {
                Write-Host "     SUCCESS: '$user' is now hidden from the GAL." -ForegroundColor Green
                Write-Host "     Note: Changes may take up to 60 minutes to reflect in Outlook." -ForegroundColor Gray
            } else {
                Write-Host "     WARNING: Command ran but status did not update. Try again or check permissions." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "     ERROR: Could not find mailbox '$user'. Check the email address and try again." -ForegroundColor Red
        Write-Host "     Details: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

# --- SHOW ---
if ($action -eq "show") {
    $user = Read-Host "     Enter user email (e.g. jsmith@yourdomain.com)"
    try {
        $mailbox = Get-Mailbox -Identity $user -ErrorAction Stop
        $currentStatus = $mailbox.HiddenFromAddressListsEnabled

        if ($currentStatus -eq $false) {
            Write-Host "     '$user' is already visible in the GAL." -ForegroundColor Yellow
        } else {
            Set-Mailbox -Identity $user -HiddenFromAddressListsEnabled $false -ErrorAction Stop
            $verify = Get-Mailbox -Identity $user | Select-Object -ExpandProperty HiddenFromAddressListsEnabled
            if ($verify -eq $false) {
                Write-Host "     SUCCESS: '$user' is now visible in the GAL." -ForegroundColor Green
                Write-Host "     Note: Changes may take up to 60 minutes to reflect in Outlook." -ForegroundColor Gray
            } else {
                Write-Host "     WARNING: Command ran but status did not update. Try again or check permissions." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "     ERROR: Could not find mailbox '$user'. Check the email address and try again." -ForegroundColor Red
        Write-Host "     Details: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

# --- CHECK ---
if ($action -eq "check") {
    $user = Read-Host "     Enter user email (e.g. jsmith@yourdomain.com)"
    try {
        $mailbox = Get-Mailbox -Identity $user -ErrorAction Stop
        $hidden  = $mailbox.HiddenFromAddressListsEnabled
        $type    = $mailbox.RecipientTypeDetails

        Write-Host "`n     --- GAL Status for $user ---" -ForegroundColor Cyan
        Write-Host "     Display Name:    $($mailbox.DisplayName)" -ForegroundColor Gray
        Write-Host "     Email:           $($mailbox.PrimarySmtpAddress)" -ForegroundColor Gray
        Write-Host "     Mailbox Type:    $type" -ForegroundColor Gray
        Write-Host "     Hidden from GAL: $hidden" -ForegroundColor $(if ($hidden) { "Yellow" } else { "Green" })

        if ($hidden) {
            Write-Host "`n     This user is currently HIDDEN from the Global Address List." -ForegroundColor Yellow
            Write-Host "     To make them visible, run this script again and choose 'show'." -ForegroundColor Gray
        } else {
            Write-Host "`n     This user is currently VISIBLE in the Global Address List." -ForegroundColor Green
            Write-Host "     To hide them, run this script again and choose 'hide'." -ForegroundColor Gray
        }
    } catch {
        Write-Host "     ERROR: Could not find mailbox '$user'. Check the email address and try again." -ForegroundColor Red
        Write-Host "     Details: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

# --- BULK ---
if ($action -eq "bulk") {
    Write-Host "     Enter the action for all users — 'hide' or 'show':" -ForegroundColor Gray
    do {
        $bulkAction = Read-Host "     Bulk action"
    } while ($bulkAction -notin @("hide", "show"))

    Write-Host "     Enter email addresses one per line." -ForegroundColor Gray
    Write-Host "     When done, type 'done' and press Enter." -ForegroundColor Gray

    $userList = @()
    do {
        $entry = Read-Host "     Email"
        if ($entry -ne "done" -and $entry -ne "") {
            $userList += $entry
        }
    } while ($entry -ne "done")

    if ($userList.Count -eq 0) {
        Write-Host "     No users entered. Exiting bulk mode." -ForegroundColor Yellow
    } else {
        Write-Host "`n     Processing $($userList.Count) user(s)..." -ForegroundColor Yellow
        $successCount = 0
        $failCount    = 0

        foreach ($u in $userList) {
            try {
                $hideValue = ($bulkAction -eq "hide")
                Set-Mailbox -Identity $u -HiddenFromAddressListsEnabled $hideValue -ErrorAction Stop
                $status = if ($hideValue) { "hidden from" } else { "visible in" }
                Write-Host "     OK: $u -> now $status GAL" -ForegroundColor Green
                $successCount++
            } catch {
                Write-Host "     FAILED: $u -> $($_.Exception.Message)" -ForegroundColor Red
                $failCount++
            }
        }

        Write-Host "`n     --- Bulk Summary ---" -ForegroundColor Cyan
        Write-Host "     Succeeded: $successCount" -ForegroundColor Green
        Write-Host "     Failed:    $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
        Write-Host "     Note: Changes may take up to 60 minutes to reflect in Outlook." -ForegroundColor Gray
    }
}

# --- REPORT ---
if ($action -eq "report") {
    Write-Host "     Pulling all mailboxes currently hidden from GAL..." -ForegroundColor Yellow
    Write-Host "     This may take a moment depending on org size..." -ForegroundColor Gray

    try {
        $hiddenMailboxes = Get-Mailbox -ResultSize Unlimited -Filter {HiddenFromAddressListsEnabled -eq $true} -ErrorAction Stop |
            Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, HiddenFromAddressListsEnabled |
            Sort-Object RecipientTypeDetails, DisplayName

        if ($hiddenMailboxes) {
            Write-Host "`n     --- Mailboxes Hidden from GAL ($($hiddenMailboxes.Count) total) ---" -ForegroundColor Cyan
            Write-Host ("     {0,-30} {1,-35} {2}" -f "Display Name", "Email", "Type") -ForegroundColor Gray
            Write-Host ("     " + "-" * 85) -ForegroundColor Gray

            foreach ($m in $hiddenMailboxes) {
                $color = switch ($m.RecipientTypeDetails) {
                    "SharedMailbox"    { "Cyan" }
                    "UserMailbox"      { "Yellow" }
                    "RoomMailbox"      { "Gray" }
                    "EquipmentMailbox" { "Gray" }
                    default            { "White" }
                }
                Write-Host ("     {0,-30} {1,-35} {2}" -f $m.DisplayName, $m.PrimarySmtpAddress, $m.RecipientTypeDetails) -ForegroundColor $color
            }

            # Save report to desktop
            $desktopPath = [Environment]::GetFolderPath("Desktop")
            if (-not $desktopPath -or -not (Test-Path $desktopPath)) { $desktopPath = "$env:USERPROFILE\Desktop" }
            if (-not (Test-Path $desktopPath)) { New-Item -ItemType Directory -Path $desktopPath -Force | Out-Null }
            $reportPath = "$desktopPath\GAL_HiddenUsers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $hiddenMailboxes | Export-Csv -Path $reportPath -NoTypeInformation
            Write-Host "`n     Report saved to: $reportPath" -ForegroundColor Cyan
        } else {
            Write-Host "     No mailboxes are currently hidden from the GAL." -ForegroundColor Green
        }
    } catch {
        Write-Host "     ERROR pulling mailbox list: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- ADD / UPDATE USER DETAILS ---
if ($action -eq "add") {
    Write-Host "`n     Enter the user's email address to add or update their GAL details." -ForegroundColor Gray
    $user = Read-Host "     Email (e.g. jsmith@yourdomain.com)"

    try {
        $mailbox = Get-Mailbox -Identity $user -ErrorAction Stop
        Write-Host "`n     Found: $($mailbox.DisplayName) <$($mailbox.PrimarySmtpAddress)>" -ForegroundColor Green
        Write-Host "     Leave any field blank to keep the existing value.`n" -ForegroundColor Gray

        # Pull current values to show as defaults
        $adUser = Get-User -Identity $user -ErrorAction SilentlyContinue

        # --- Collect fields ---
        Write-Host "     Current First Name:    $($adUser.FirstName)" -ForegroundColor Gray
        $firstName = Read-Host "     New First Name"

        Write-Host "     Current Last Name:     $($adUser.LastName)" -ForegroundColor Gray
        $lastName = Read-Host "     New Last Name"

        Write-Host "     Current Display Name:  $($mailbox.DisplayName)" -ForegroundColor Gray
        $displayName = Read-Host "     New Display Name"

        Write-Host "     Current Job Title:     $($adUser.Title)" -ForegroundColor Gray
        $jobTitle = Read-Host "     New Job Title"

        Write-Host "     Current Company:       $($adUser.Company)" -ForegroundColor Gray
        $company = Read-Host "     New Company Name"

        Write-Host "     Current Phone:         $($adUser.Phone)" -ForegroundColor Gray
        $phone = Read-Host "     New Phone Number"

        # --- Confirm before applying ---
        Write-Host "`n     --- Review Changes ---" -ForegroundColor Cyan
        if ($firstName)   { Write-Host "     First Name:   $firstName" -ForegroundColor White }
        if ($lastName)    { Write-Host "     Last Name:    $lastName" -ForegroundColor White }
        if ($displayName) { Write-Host "     Display Name: $displayName" -ForegroundColor White }
        if ($jobTitle)    { Write-Host "     Job Title:    $jobTitle" -ForegroundColor White }
        if ($company)     { Write-Host "     Company:      $company" -ForegroundColor White }
        if ($phone)       { Write-Host "     Phone:        $phone" -ForegroundColor White }

        $blankCount = @($firstName, $lastName, $displayName, $jobTitle, $company, $phone) | Where-Object { $_ -eq "" } | Measure-Object | Select-Object -ExpandProperty Count
        if ($blankCount -eq 6) {
            Write-Host "`n     No changes entered. Exiting." -ForegroundColor Yellow
        } else {
            Write-Host "`n     Type 'confirm' to apply or 'exit' to cancel." -ForegroundColor Yellow
            do {
                $confirmChoice = Read-Host "     Choice"
            } while ($confirmChoice -ne "confirm" -and $confirmChoice -ne "exit")

            if ($confirmChoice -eq "confirm") {
                $errors = @()

                # Build Set-User params
                $userParams = @{ Identity = $user }
                if ($firstName)   { $userParams["FirstName"] = $firstName }
                if ($lastName)    { $userParams["LastName"]  = $lastName }
                if ($displayName) { $userParams["DisplayName"] = $displayName }
                if ($jobTitle)    { $userParams["Title"]     = $jobTitle }
                if ($company)     { $userParams["Company"]   = $company }
                if ($phone)       { $userParams["Phone"]     = $phone }

                try {
                    Set-User @userParams -ErrorAction Stop
                    Write-Host "     User details updated." -ForegroundColor Green
                } catch {
                    $errors += "Set-User failed: $($_.Exception.Message)"
                }

                # Update display name on mailbox separately if provided
                if ($displayName) {
                    try {
                        Set-Mailbox -Identity $user -DisplayName $displayName -ErrorAction Stop
                        Write-Host "     Mailbox display name updated." -ForegroundColor Green
                    } catch {
                        $errors += "Set-Mailbox DisplayName failed: $($_.Exception.Message)"
                    }
                }

                # Verify and show final state
                Write-Host "`n     --- Final GAL Details for $user ---" -ForegroundColor Cyan
                $updated = Get-User -Identity $user -ErrorAction SilentlyContinue
                $updatedMailbox = Get-Mailbox -Identity $user -ErrorAction SilentlyContinue
                Write-Host "     Display Name: $($updatedMailbox.DisplayName)" -ForegroundColor Green
                Write-Host "     First Name:   $($updated.FirstName)" -ForegroundColor Green
                Write-Host "     Last Name:    $($updated.LastName)" -ForegroundColor Green
                Write-Host "     Job Title:    $($updated.Title)" -ForegroundColor Green
                Write-Host "     Company:      $($updated.Company)" -ForegroundColor Green
                Write-Host "     Phone:        $($updated.Phone)" -ForegroundColor Green
                Write-Host "     Email:        $($updatedMailbox.PrimarySmtpAddress)" -ForegroundColor Green

                if ($errors.Count -gt 0) {
                    Write-Host "`n     Some errors occurred:" -ForegroundColor Red
                    foreach ($e in $errors) { Write-Host "     - $e" -ForegroundColor Red }
                } else {
                    Write-Host "`n     All changes applied successfully." -ForegroundColor Green
                    Write-Host "     Note: Changes may take up to 60 minutes to reflect in Outlook's GAL." -ForegroundColor Gray
                }
            } else {
                Write-Host "     Cancelled. No changes made." -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "     ERROR: Could not find mailbox '$user'. Check the email address and try again." -ForegroundColor Red
        Write-Host "     Details: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

Write-Host "`n=== GALManager Complete ===" -ForegroundColor Cyan
