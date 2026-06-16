# PowerShell IT Automation Toolkit

A production-ready collection of 20+ PowerShell scripts for enterprise Windows IT support. Built for real helpdesk environments — one-word alias commands, consistent color-coded output, and zero GUI dependency.

## Features

- **One-word execution** — `morning`, `netdiag`, `vpnrepair`, `outlookfix` etc. via PowerShell profile aliases
- **Color-coded output** — Cyan headers, Green success, Yellow warnings, Red errors on every script
- **Recommended Actions** — every script ends with a summary of what was found and what to do next
- **run/skip prompts** — optional steps use clear `run`/`skip` keypresses, not Y/N
- **OneDrive-safe** — uses `[Environment]::GetFolderPath()` to handle redirected desktop paths

## Script Categories

### Morning Startup
| Script | Alias | Description |
|--------|-------|-------------|
| `MorningStartup.ps1` | `morning` | Daily reset — clears all caches (Teams, Slack, Outlook, browser, VPN), runs disk/RAM/network health checks |

### Network
| Script | Alias | Description |
|--------|-------|-------------|
| `NetDiag.ps1` | `netdiag` | Full network diagnostic — ping, DNS, gateway, adapter status |
| `NetReset.ps1` | `netreset` | Resets TCP/IP stack, Winsock, flushes DNS |
| `NetMonitor.ps1` | `netmon` | Real-time network activity monitor |
| `WiFiReport.ps1` | `wifireport` | Generates Wi-Fi adapter and connection report to desktop |
| `ProxyChecker.ps1` | `proxychk` | Checks and reports proxy configuration |

### VPN
| Script | Alias | Description |
|--------|-------|-------------|
| `VPNRepair.ps1` | `vpnrepair` | Cisco Secure Client 5.x repair — uses `vpncli state` for status detection (no visible Windows adapter in CS Client 5.x) |

### Printing
| Script | Alias | Description |
|--------|-------|-------------|
| `PrinterDiag.ps1` | `printdiag` | Diagnoses printer queues, checks job status per printer |
| `PrintSpoolerReset.ps1` | `spooler` | Resets Print Spooler, clears stuck jobs |

### App Repair
| Script | Alias | Description |
|--------|-------|-------------|
| `OutlookRepair.ps1` | `outlookfix` | Kills Outlook, clears cache, repairs via OfficeClickToRun, relaunches |
| `SlackRepair.ps1` | `slackfix` | Clears Slack cache and relaunches |
| `BrowserRepair.ps1` | `browserfix` | Repairs Chrome/Edge — cache clear, profile check |
| `RemoveChrome.ps1` | `chromerm` | Safe Chrome removal preserving user profile data |
| `ReinstallChrome.ps1` | `chromein` | Backs up profile, fresh installs Chrome, restores profile |

### System & Performance
| Script | Alias | Description |
|--------|-------|-------------|
| `SpeedBoost.ps1` | `speedboost` | Performance optimization — clears memory, temp files, startup items |
| `DiskCleanup.ps1` | `diskclean` | Disk cleanup with size reporting before and after |
| `WindowsUpdateFix.ps1` | `wufix` | Resets Windows Update components, clears cache, reruns check |
| `AppCrashDiag.ps1` | `crashdiag` | Reads Windows Event Log for application crash events |
| `UserProfileDiag.ps1` | `profilediag` | Diagnoses corrupted or temp user profile issues |
| `RemoteDesktopFix.ps1` | `rdpfix` | Repairs RDP settings, clears credentials, checks firewall rules |

### Microsoft 365 / Exchange
| Script | Alias | Description |
|--------|-------|-------------|
| `GALManager.ps1` | `gal` | Exchange Online GAL management — hide/show/check/bulk/report/add options |

### Infrastructure
| Script | Alias | Description |
|--------|-------|-------------|
| `MapDrives.ps1` | `mapdrives` | Maps network drives to file servers |
| `Setup-Aliases.ps1` | *(run once)* | Builds PowerShell profile with all one-word alias commands |

## Setup

### 1. Clone the repo
```powershell
git clone https://github.com/YOUR_USERNAME/powershell-it-toolkit.git
```

### 2. Update paths
Open `Setup-Aliases.ps1` and update `$scriptsPath` to your local scripts folder:
```powershell
$scriptsPath = "C:\Users\YOUR_USERNAME\Documents\PowerShell Scripts"
```

### 3. Run setup (as Administrator)
```powershell
.\Setup-Aliases.ps1
```

### 4. Restart PowerShell
All aliases are now available. Type `morning` to run your first script.

## Usage Examples

```powershell
# Start the day
morning

# Network is slow
netdiag

# VPN won't connect
vpnrepair

# Outlook crashing
outlookfix

# Printer stuck
spooler

# Exchange admin - hide user from GAL
gal
```

## Technical Notes

- **Cisco Secure Client 5.x**: Uses kernel-mode tunnel driver — no visible Windows network adapter. `vpncli state` is the only reliable status check.
- **OneDrive paths**: All file output uses `[Environment]::GetFolderPath("Desktop")` to handle redirected desktop paths.
- **Encoding**: All scripts use clean ASCII — no smart quotes or em dashes that corrupt syntax.
- **Admin rights**: Scripts that modify system settings will prompt for elevation automatically.

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Administrator rights (for most scripts)
- Exchange Online PowerShell module (for `GALManager.ps1`)

## License

MIT — free to use, modify, and distribute. Attribution appreciated.

---

Built by [Jaxson Tanner](https://jaxsonzane.com) — IT Automation & Support Specialist
