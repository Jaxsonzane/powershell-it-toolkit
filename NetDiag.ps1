# ============================================================
#  NetDiag.ps1 - Full Network Diagnostic
#  Run as Administrator in PowerShell
# ============================================================

# Resolve Desktop path safely — handles OneDrive redirection
$desktopPath = [Environment]::GetFolderPath("Desktop")
if (-not $desktopPath -or -not (Test-Path $desktopPath)) {
    $desktopPath = "$env:USERPROFILE\Desktop"
}
if (-not (Test-Path $desktopPath)) {
    New-Item -ItemType Directory -Path $desktopPath -Force | Out-Null
}
$logPath = "$desktopPath\NetDiag_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$results = @()

function Log($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
    $script:results += $msg
}

Log "`n=== NetDiag - Network Diagnostic Report ===" "Cyan"
Log "Run by: $env:USERNAME | $(Get-Date)" "Gray"
Log "Computer: $env:COMPUTERNAME`n" "Gray"

# --- 1. Network Adapters ---
Log "[1/6] Active Network Adapters..." "Yellow"
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
if ($adapters) {
    foreach ($a in $adapters) {
        Log "     Name: $($a.Name) | Status: $($a.Status) | Speed: $($a.LinkSpeed)" "Green"
    }
} else {
    Log "     WARNING: No active adapters found!" "Red"
}

# --- 2. IP Configuration ---
Log "`n[2/6] IP Configuration..." "Yellow"
$ipConfigs = Get-NetIPAddress | Where-Object { $_.AddressFamily -eq "IPv4" -and $_.IPAddress -notmatch "^169|^127" }
foreach ($ip in $ipConfigs) {
    Log "     Interface: $($ip.InterfaceAlias) | IP: $($ip.IPAddress) | Prefix: $($ip.PrefixLength)" "Green"
}

# --- 3. Default Gateway Ping ---
Log "`n[3/6] Pinging Default Gateway..." "Yellow"
$gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).NextHop
if ($gateway) {
    $ping = Test-Connection -ComputerName $gateway -Count 3 -ErrorAction SilentlyContinue
    if ($ping) {
        $avg = [math]::Round(($ping | Measure-Object ResponseTime -Average).Average, 1)
        Log "     Gateway: $gateway | Avg Response: ${avg}ms" "Green"
    } else {
        Log "     WARNING: Cannot reach gateway $gateway" "Red"
    }
} else {
    Log "     WARNING: No default gateway found!" "Red"
}

# --- 4. DNS Resolution Test ---
Log "`n[4/6] DNS Resolution Test..." "Yellow"
$testHosts = @("google.com", "microsoft.com", "cloudflare.com")
foreach ($h in $testHosts) {
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($h) | Select-Object -First 1
        Log "     $h -> $($resolved.IPAddressToString)" "Green"
    } catch {
        Log "     FAILED to resolve $h" "Red"
    }
}

# --- 5. Internet Connectivity (HTTP) ---
Log "`n[5/6] Internet Connectivity Test..." "Yellow"
$testUrls = @("https://www.google.com", "https://www.cloudflare.com")
foreach ($url in $testUrls) {
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Log "     $url -> HTTP $($response.StatusCode) OK" "Green"
    } catch {
        Log "     FAILED to reach $url" "Red"
    }
}

# --- 6. Traceroute to 8.8.8.8 ---
Log "`n[6/6] Traceroute to 8.8.8.8..." "Yellow"
$trace = Test-NetConnection -ComputerName "8.8.8.8" -TraceRoute -ErrorAction SilentlyContinue
if ($trace.TraceRoute) {
    $hop = 1
    foreach ($t in $trace.TraceRoute) {
        Log "     Hop $hop`: $t" "Gray"
        $hop++
    }
} else {
    Log "     Traceroute failed or blocked." "Red"
}

# --- Save Log ---
Log "`n=== Diagnostic Complete ===" "Cyan"
$script:results | Out-File -FilePath $logPath -Encoding UTF8
Write-Host "`nLog saved to: $logPath" -ForegroundColor Cyan
