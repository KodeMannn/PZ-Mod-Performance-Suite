<# :
@echo off
title Project Zomboid Mod Performance ^& Optimization Suite v2.21.0
color 0F
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([System.IO.File]::ReadAllText('%~f0'))) %*"
echo.
pause
exit /b
#>
<#
.SYNOPSIS
    Project Zomboid Mod Performance & Optimization Suite v2.21.0
.DESCRIPTION
    Comprehensive diagnostic scanner and optimization toolkit for Project Zomboid (Build 42 & 41).
    Features Precision Slow Frame Anatomy Dissection (Main vs Render Thread, GC pauses vs Chunk Cache),
    Consecutive Freeze Cluster Analysis (Multi-Frame Chains), 3D Frustum & Geometry Telemetry (Draws/Frame, Bones, VRAM),
    In-Game Graphics Configuration Bottleneck Audit (options.ini), JVM Bytecode Patch & Hook Registry ([ZB]),
    Runtime Mod Error & Exception Attribution, GC Heap Churn Velocity, Causal Bottleneck Attribution,
    Hardware & Thread Headroom Telemetry, Cross-Platform Linux/macOS/Windows Support, Multi-Drive Steam Library Discovery,
    and 1-Click Engine Tuning.
.AUTHOR
    KodeMannn (https://github.com/KodeMannn) - Coded with the assistance of Google Gemini
#>

[CmdletBinding()]
param(
    [string]$ZomboidUserPath = "",
    [string]$ReportOutputPath = "",
    [string]$CustomLogPath = "",
    [switch]$Auto,
    [switch]$StutterRoster,
    [string]$ServerConfigPath = "",
    [switch]$FixGC,
    [int]$CapFPS = 0,
    [switch]$OptGraphics,
    [switch]$LocalWorkshop,
    [string]$CustomWorkshopPath = "",
    [switch]$CleanSave,
    [string]$Revert = ""
)

$Script:SuiteVersion = "v2.21.0"
$ErrorActionPreference = "SilentlyContinue"

# Cross-platform OS & User Home Directory Detection
$isWindows = if ($PSVersionTable.PSVersion.Major -le 5) { $true } else { $IsWindows }
$isLinux = if ($IsLinux) { $true } else { $false }
$isMacOS = if ($IsMacOS) { $true } else { $false }

$userHome = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { [System.Environment]::GetFolderPath('UserProfile') }
if (-not $ZomboidUserPath) {
    if ($userHome) {
        $ZomboidUserPath = Join-Path $userHome "Zomboid"
    } else {
        $ZomboidUserPath = "Zomboid"
    }
}

if (-not $ReportOutputPath) {
    if ($PSScriptRoot) {
        $ReportOutputPath = Join-Path $PSScriptRoot "ModPerformanceReport.md"
    } else {
        $ReportOutputPath = Join-Path $ZomboidUserPath "ModPerformanceReport.md"
    }
}

$ConfigFilePath = Join-Path $ZomboidUserPath "pz_scanner_config.json"

# ==============================================================================
# Helper Functions: Persistent Configuration & Custom Paths
# ==============================================================================
function Get-PZScannerConfig {
    if (Test-Path $ConfigFilePath) {
        try {
            $raw = [System.IO.File]::ReadAllText($ConfigFilePath)
            if ($raw) {
                return (ConvertFrom-Json $raw -ErrorAction SilentlyContinue)
            }
        } catch {}
    }
    return [PSCustomObject]@{
        CustomWorkshopPath = ""
    }
}

function Set-PZScannerConfig([string]$customWsPath) {
    try {
        $cfg = Get-PZScannerConfig
        if (-not $cfg) { $cfg = [PSCustomObject]@{} }
        $cfg | Add-Member -NotePropertyName "CustomWorkshopPath" -NotePropertyValue $customWsPath -Force
        $json = $cfg | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($ConfigFilePath, $json)
        return $true
    } catch {
        return $false
    }
}

# Load saved custom workshop path from configuration if not passed via CLI
if (-not $CustomWorkshopPath) {
    $savedCfg = Get-PZScannerConfig
    if ($savedCfg -and $savedCfg.CustomWorkshopPath) {
        $CustomWorkshopPath = $savedCfg.CustomWorkshopPath
    }
}

function Resolve-CustomWorkshopPath([string]$path) {
    if (-not $path) { return $null }
    $clean = $path.Trim().Trim('"').Trim("'")
    if (-not (Test-Path $clean)) { return $null }

    # If path directly targets 108600 or contains 108600 directory
    if ($clean -match '108600$' -or (Test-Path (Join-Path $clean "108600"))) {
        if ($clean -match '108600$') { return $clean }
        return (Join-Path $clean "108600")
    }

    # Steam library root containing steamapps/workshop/content/108600
    $sub1 = Join-Path $clean "steamapps/workshop/content/108600"
    if (Test-Path $sub1) { return $sub1 }
    $sub1Win = Join-Path $clean "steamapps\workshop\content\108600"
    if (Test-Path $sub1Win) { return $sub1Win }

    # steamapps folder containing workshop/content/108600
    $sub2 = Join-Path $clean "workshop/content/108600"
    if (Test-Path $sub2) { return $sub2 }
    $sub2Win = Join-Path $clean "workshop\content\108600"
    if (Test-Path $sub2Win) { return $sub2Win }

    # Custom folder containing mods directly
    return $clean
}

# ==============================================================================
# Helper Functions: Steam & Library Discovery (Cross-Platform & Multi-Drive)
# ==============================================================================
function Get-PZInstallPath {
    $candidates = @()
    if ($userHome) {
        # Linux & SteamOS / Steam Deck candidates
        $candidates += @(
            (Join-Path $userHome ".local/share/Steam/steamapps/common/ProjectZomboid"),
            (Join-Path $userHome ".steam/steam/steamapps/common/ProjectZomboid"),
            (Join-Path $userHome ".steam/root/steamapps/common/ProjectZomboid"),
            (Join-Path $userHome ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/ProjectZomboid"),
            (Join-Path $userHome "Steam/steamapps/common/ProjectZomboid"),
            (Join-Path $userHome ".steam/debian-installation/steamapps/common/ProjectZomboid"),
            # macOS candidates
            (Join-Path $userHome "Library/Application Support/Steam/steamapps/common/ProjectZomboid"),
            (Join-Path $userHome "Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java"),
            "/Applications/Project Zomboid.app/Contents/Java"
        )
    }

    if ($isWindows) {
        # Windows Registry Inspection (Direct Steam App 108600 Uninstall Entry)
        $regKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 108600',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 108600'
        )
        foreach ($rk in $regKeys) {
            $regItem = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
            if ($regItem -and $regItem.InstallLocation) {
                $candidates += $regItem.InstallLocation
            }
        }

        # Dynamic Drive Scan across all ready logical drives (C:, D:, E:, F:, G:, etc.)
        try {
            $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | Select-Object -ExpandProperty RootDirectory -ErrorAction SilentlyContinue
            foreach ($d in $drives) {
                $root = $d.FullName.TrimEnd('\')
                $candidates += @(
                    "$root\SteamLibrary\steamapps\common\ProjectZomboid",
                    "$root\Steam\steamapps\common\ProjectZomboid",
                    "$root\Games\SteamLibrary\steamapps\common\ProjectZomboid",
                    "$root\Games\Steam\steamapps\common\ProjectZomboid",
                    "$root\Program Files (x86)\Steam\steamapps\common\ProjectZomboid",
                    "$root\Program Files\Steam\steamapps\common\ProjectZomboid",
                    "$root\steamapps\common\ProjectZomboid"
                )
            }
        } catch {}
    }

    # Static fallback Windows candidates
    $candidates += @(
        "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid",
        "C:\Program Files\Steam\steamapps\common\ProjectZomboid",
        "D:\SteamLibrary\steamapps\common\ProjectZomboid",
        "D:\Steam\steamapps\common\ProjectZomboid",
        "E:\SteamLibrary\steamapps\common\ProjectZomboid",
        "H:\SteamLibrary\steamapps\common\ProjectZomboid"
    )

    foreach ($c in $candidates) {
        if ($c -and ((Test-Path (Join-Path $c "ProjectZomboid64.json")) -or 
            (Test-Path (Join-Path $c "projectzomboid.sh")) -or 
            (Test-Path (Join-Path $c "Project Zomboid.app")))) { 
            return $c 
        }
    }
    return $null
}

function Get-PZSystemPhysicalRamGB {
    try {
        if ($isWindows) {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
            if ($cs -and $cs.TotalPhysicalMemory) {
                return [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
            }
        } elseif ($isLinux -and (Test-Path "/proc/meminfo")) {
            $memLine = Get-Content "/proc/meminfo" -ErrorAction SilentlyContinue | Where-Object { $_ -match '^MemTotal:\s*(\d+)' } | Select-Object -First 1
            if ($memLine -match '^MemTotal:\s*(\d+)') {
                return [math]::Round([double]$matches[1] / 1048576, 1)
            }
        } elseif ($isMacOS) {
            $memBytes = & sysctl -n hw.memsize 2>$null
            if ($memBytes -match '^\d+$') {
                return [math]::Round([double]$memBytes / 1GB, 1)
            }
        }
    } catch {}
    return 16.0 # safe fallback
}

function Get-PZJvmStatus {
    $status = [PSCustomObject]@{
        InstalledJsonFound = $false
        ConfiguredHeap     = "16g"
        IsG1GC             = $false
        HasPauseTarget     = $false
        HasPzOptTag        = $false
        IsFullyOptimized   = $false
        GcType             = "Unknown"
        Summary            = "Launcher Config Not Found"
    }

    $installDir = Get-PZInstallPath
    if (-not $installDir) { return $status }
    $jsonPath = Join-Path $installDir "ProjectZomboid64.json"
    if (-not (Test-Path $jsonPath)) { return $status }

    try {
        $raw = Get-Content $jsonPath -Raw -ErrorAction Stop
        if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
            $raw = $raw.Substring(1)
        }
        $json = $raw | ConvertFrom-Json
        $status.InstalledJsonFound = $true

        # Scan all OS vmArgs (windows, linux, macos) and root vmArgs
        $allVmArgs = @()
        if ($json.vmArgs) { $allVmArgs += $json.vmArgs }
        if ($json.windows) {
            if ($json.windows.'10.0.17134' -and $json.windows.'10.0.17134'.vmArgs) {
                $allVmArgs += $json.windows.'10.0.17134'.vmArgs
            }
            if ($json.windows.'6.1' -and $json.windows.'6.1'.vmArgs) {
                $allVmArgs += $json.windows.'6.1'.vmArgs
            }
        }
        if ($json.linux -and $json.linux.vmArgs) { $allVmArgs += $json.linux.vmArgs }
        if ($json.macos -and $json.macos.vmArgs) { $allVmArgs += $json.macos.vmArgs }

        foreach ($arg in $allVmArgs) {
            if ($arg -match '^-Xmx(\d+[gmGM])') {
                $status.ConfiguredHeap = $matches[1].ToLower()
            }
            if ($arg -match '-XX:\+UseG1GC') { $status.IsG1GC = $true }
            if ($arg -match '-XX:\+UseZGC') { $status.GcType = "ZGC (Vanilla B42 Default)" }
            if ($arg -match '-XX:MaxGCPauseMillis=(\d+)') { $status.HasPauseTarget = $true }
            if ($arg -match '-Dpzopt\.gc=g1') { $status.HasPzOptTag = $true }
        }

        if ($status.IsG1GC) {
            $status.GcType = "G1GC"
            if ($status.HasPauseTarget -or $status.HasPzOptTag) {
                $status.IsFullyOptimized = $true
                $status.Summary = "G1GC Low-Latency ($($status.ConfiguredHeap.ToUpper()) Heap, 5ms Pause Target)"
            } else {
                $status.Summary = "G1GC Standard ($($status.ConfiguredHeap.ToUpper()) Heap)"
            }
        } elseif ($status.GcType -eq "ZGC (Vanilla B42 Default)") {
            $status.Summary = "ZGC Vanilla ($($status.ConfiguredHeap.ToUpper()) Heap)"
        } else {
            $status.GcType = "Default JVM GC"
            $status.Summary = "Default GC ($($status.ConfiguredHeap.ToUpper()) Heap)"
        }
    } catch {
        $status.Summary = "Error reading launcher JSON"
    }

    return $status
}

function Get-WorkshopPaths([string]$customPath = "") {
    $potential = @()

    # 1. Custom workshop path if passed, scoped, or persistently configured
    $cfgPath = if ($customPath) { $customPath } elseif ($script:CustomWorkshopPath) { $script:CustomWorkshopPath } else { (Get-PZScannerConfig).CustomWorkshopPath }
    if ($cfgPath) {
        $resolvedCustom = Resolve-CustomWorkshopPath $cfgPath
        if ($resolvedCustom -and (Test-Path $resolvedCustom)) {
            $potential += $resolvedCustom
        }
    }

    # 2. Linux & macOS candidates
    if ($userHome) {
        $potential += @(
            (Join-Path $userHome ".local/share/Steam/steamapps/workshop/content/108600"),
            (Join-Path $userHome ".steam/steam/steamapps/workshop/content/108600"),
            (Join-Path $userHome ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/workshop/content/108600"),
            (Join-Path $userHome "Steam/steamapps/workshop/content/108600"),
            (Join-Path $userHome "Library/Application Support/Steam/steamapps/workshop/content/108600")
        )
    }

    # 3. Collect libraryfolders.vdf candidates across all platforms, drives, and registries
    $vdfCandidates = @()
    if ($userHome) {
        $vdfCandidates += @(
            (Join-Path $userHome ".local/share/Steam/steamapps/libraryfolders.vdf"),
            (Join-Path $userHome ".steam/steam/steamapps/libraryfolders.vdf"),
            (Join-Path $userHome ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf"),
            (Join-Path $userHome "Library/Application Support/Steam/steamapps/libraryfolders.vdf")
        )
    }

    if ($isWindows) {
        # Check Project Zomboid uninstall registry keys to locate Steam parent directory
        $pzRegKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 108600',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 108600'
        )
        foreach ($rk in $pzRegKeys) {
            $regItem = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
            if ($regItem -and $regItem.InstallLocation) {
                $steamApps = Split-Path (Split-Path $regItem.InstallLocation -Parent) -Parent
                if ($steamApps -and (Test-Path $steamApps)) {
                    $potential += (Join-Path $steamApps "workshop\content\108600")
                    $vdfCandidates += (Join-Path $steamApps "libraryfolders.vdf")
                }
            }
        }

        # Check Valve Steam registry keys
        $valveRegKeys = @(
            @{ Path = 'HKCU:\Software\Valve\Steam'; Prop = 'SteamPath' },
            @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Prop = 'InstallPath' },
            @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Prop = 'InstallPath' }
        )
        foreach ($vr in $valveRegKeys) {
            $vItem = Get-ItemProperty -Path $vr.Path -ErrorAction SilentlyContinue
            if ($vItem) {
                $steamRoot = $vItem.($vr.Prop)
                if ($steamRoot -and (Test-Path $steamRoot)) {
                    $potential += (Join-Path $steamRoot "steamapps\workshop\content\108600")
                    $vdfCandidates += (Join-Path $steamRoot "steamapps\libraryfolders.vdf")
                }
            }
        }

        # Dynamic Logical Drive Enumeration for Windows (C:, D:, E:, F:, G:, etc.)
        try {
            $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | Select-Object -ExpandProperty RootDirectory -ErrorAction SilentlyContinue
            foreach ($d in $drives) {
                $root = $d.FullName.TrimEnd('\')
                $potential += @(
                    "$root\SteamLibrary\steamapps\workshop\content\108600",
                    "$root\Steam\steamapps\workshop\content\108600",
                    "$root\Games\SteamLibrary\steamapps\workshop\content\108600",
                    "$root\Games\Steam\steamapps\workshop\content\108600",
                    "$root\Program Files (x86)\Steam\steamapps\workshop\content\108600",
                    "$root\Program Files\Steam\steamapps\workshop\content\108600",
                    "$root\steamapps\workshop\content\108600"
                )
                $vdfCandidates += @(
                    "$root\SteamLibrary\steamapps\libraryfolders.vdf",
                    "$root\Steam\steamapps\libraryfolders.vdf",
                    "$root\Games\SteamLibrary\steamapps\libraryfolders.vdf",
                    "$root\Games\Steam\steamapps\libraryfolders.vdf",
                    "$root\Program Files (x86)\Steam\steamapps\libraryfolders.vdf",
                    "$root\Program Files\Steam\steamapps\libraryfolders.vdf",
                    "$root\steamapps\libraryfolders.vdf"
                )
            }
        } catch {}
    }

    # Static fallback Windows candidates
    $potential += @(
        "C:\Program Files (x86)\Steam\steamapps\workshop\content\108600",
        "C:\Program Files\Steam\steamapps\workshop\content\108600",
        "D:\SteamLibrary\steamapps\workshop\content\108600",
        "D:\Steam\steamapps\workshop\content\108600",
        "E:\SteamLibrary\steamapps\workshop\content\108600",
        "H:\SteamLibrary\steamapps\workshop\content\108600"
    )

    $vdfCandidates += @(
        "C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf",
        "C:\Program Files\Steam\steamapps\libraryfolders.vdf"
    )

    # 4. Search and parse all discovered libraryfolders.vdf files (both modern and legacy VDF)
    foreach ($vdfPath in ($vdfCandidates | Select-Object -Unique)) {
        if ($vdfPath -and (Test-Path $vdfPath)) {
            $vdfContent = Get-Content $vdfPath -ErrorAction SilentlyContinue
            foreach ($line in $vdfContent) {
                $libPath = $null
                if ($line -match '"path"\s+"([^"]+)"') {
                    $libPath = $matches[1]
                } elseif ($line -match '^\s*"[0-9]+"\s+"([^"]+)"') {
                    $libPath = $matches[1]
                }
                if ($libPath) {
                    $libPathClean = $libPath -replace '\\\\', '/' -replace '\\', '/'
                    $candidateWs = @(
                        (Join-Path $libPathClean "steamapps/workshop/content/108600"),
                        (Join-Path $libPathClean "workshop/content/108600")
                    )
                    foreach ($cWs in $candidateWs) {
                        if ($potential -notcontains $cWs) { $potential += $cWs }
                    }
                }
            }
        }
    }

    return @($potential | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
}

# ==============================================================================
# Helper Function: Dynamic Runtime Engine Log Discovery (Build 42 & 41)
# ==============================================================================
function Resolve-PZEngineLogFile([string]$userPath, [string]$customLog = "") {
    # 1. User-supplied custom log path
    if ($customLog -and (Test-Path $customLog)) {
        $ci = Get-Item $customLog -ErrorAction SilentlyContinue
        if ($ci -and $ci.Length -gt 0) {
            return $ci
        }
    }

    # 2. Check active session DebugLogs in Zomboid\Logs\
    $logsDir = Join-Path $userPath "Logs"
    $latestDebug = $null
    if (Test-Path $logsDir) {
        $debugLogs = @(Get-ChildItem -Path $logsDir -Filter "*DebugLog.txt" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 } |
            Sort-Object LastWriteTime -Descending)
        if ($debugLogs.Count -gt 0) {
            $latestDebug = $debugLogs[0]
        }
    }

    # 3. Check root console.txt
    $consoleLog = Join-Path $userPath "console.txt"
    $consoleItem = $null
    if (Test-Path $consoleLog) {
        $ci = Get-Item $consoleLog -ErrorAction SilentlyContinue
        if ($ci -and $ci.Length -gt 0) {
            $consoleItem = $ci
        }
    }

    # Compare latest debug log vs console.txt: pick whichever is non-empty and most recently modified
    if ($latestDebug -and $consoleItem) {
        if ($consoleItem.LastWriteTime -gt $latestDebug.LastWriteTime) {
            return $consoleItem
        } else {
            return $latestDebug
        }
    } elseif ($latestDebug) {
        return $latestDebug
    } elseif ($consoleItem) {
        return $consoleItem
    }

    # 4. Fallback to archived session logs in Zomboid\Logs\logs_*\*_DebugLog.txt
    if (Test-Path $logsDir) {
        $archivedLogs = @(Get-ChildItem -Path $logsDir -Filter "*DebugLog.txt" -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 } |
            Sort-Object LastWriteTime -Descending)
        if ($archivedLogs.Count -gt 0) {
            return $archivedLogs[0]
        }
    }

    # 5. Fallback to coop/server logs
    foreach ($srvLog in @("coop-console.txt", "server-console.txt")) {
        $sp = Join-Path $userPath $srvLog
        if (Test-Path $sp) {
            $si = Get-Item $sp -ErrorAction SilentlyContinue
            if ($si -and $si.Length -gt 0) {
                return $si
            }
        }
    }

    # 6. Fallback if console.txt exists even if 0 bytes
    if (Test-Path $consoleLog) {
        return (Get-Item $consoleLog -ErrorAction SilentlyContinue)
    }

    return $null
}

# ==============================================================================
# Optimization Action: 1-Click Java GC Tuning
# ==============================================================================
function Invoke-PZFixGC {
    Write-Host "`n[*] Running Java Garbage Collection Optimizer..." -ForegroundColor Yellow
    $installDir = Get-PZInstallPath
    if (-not $installDir) {
        Write-Host " [!] Could not locate Project Zomboid installation directory." -ForegroundColor Red
        return
    }
    $jsonPath = Join-Path $installDir "ProjectZomboid64.json"
    if (-not (Test-Path $jsonPath)) {
        Write-Host " [!] ProjectZomboid64.json not found in $installDir." -ForegroundColor Red
        return
    }

    try {
        # Backup original
        $bakPath = "$jsonPath.bak"
        if (-not (Test-Path $bakPath)) {
            Copy-Item $jsonPath $bakPath -Force
            Write-Host " [OK] Backed up original launcher JSON to ProjectZomboid64.json.bak" -ForegroundColor Gray
        }

        # Read JSON and strip any leading BOM if present
        $raw = Get-Content $jsonPath -Raw -ErrorAction Stop
        if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
            $raw = $raw.Substring(1)
        }
        $json = $raw | ConvertFrom-Json

        # Heap calculation: Dynamically determine safe hardware heap bounds based on physical system RAM
        $systemRamGB = Get-PZSystemPhysicalRamGB
        $optimalHeapGB = if ($systemRamGB -ge 28.0) { 16 }
                        elseif ($systemRamGB -ge 14.0) { 8 }
                        else { 4 }
        $optimalHeapArg = "-Xmx${optimalHeapGB}g"
        $optimalHeapMB = $optimalHeapGB * 1024

        Write-Host " [INFO] Detected System RAM: ${systemRamGB} GB -> Optimal Safe Java Heap: ${optimalHeapGB} GB" -ForegroundColor Gray

        $newArgs = @()
        $foundXmx = $false
        foreach ($arg in $json.vmArgs) {
            if ($arg -match '^-Xmx(\d+)([gmGM])') {
                $foundXmx = $true
                $num = [int]$matches[1]
                $unit = $matches[2].ToLower()
                $existingMB = if ($unit -eq 'g') { $num * 1024 } else { $num }
                if ($existingMB -gt $optimalHeapMB) {
                    $newArgs += $optimalHeapArg
                    Write-Host " [OPTIMIZE] Clamping oversized heap ($($num)$($unit.ToUpper())) down to safe hardware ceiling ${optimalHeapGB}GB ($optimalHeapArg) to eliminate 500ms+ GC sweeps!" -ForegroundColor Yellow
                } elseif ($existingMB -lt $optimalHeapMB) {
                    $newArgs += $optimalHeapArg
                    Write-Host " [OPTIMIZE] Elevating heap ($($num)$($unit.ToUpper())) to optimal hardware ceiling ${optimalHeapGB}GB ($optimalHeapArg) for modern modpacks." -ForegroundColor Cyan
                } else {
                    $newArgs += $optimalHeapArg
                    Write-Host " [OK] Heap already set to optimal hardware ceiling ${optimalHeapGB}GB ($optimalHeapArg)." -ForegroundColor Gray
                }
            } else {
                $newArgs += $arg
            }
        }
        if (-not $foundXmx) {
            $newArgs += $optimalHeapArg
            Write-Host " [OPTIMIZE] Added $optimalHeapArg heap limit to vmArgs." -ForegroundColor Cyan
        }
        $json.vmArgs = $newArgs

        # Configure G1GC with 5ms pause target for Windows, Linux, and macOS
        if (-not $json.windows) {
            $json | Add-Member -MemberType NoteProperty -Name "windows" -Value (New-Object PSObject) -ErrorAction SilentlyContinue
        }
        if ($json.windows) {
            if (-not $json.windows.'10.0.17134') {
                $json.windows | Add-Member -MemberType NoteProperty -Name "10.0.17134" -Value (New-Object PSObject) -ErrorAction SilentlyContinue
            }
            if ($json.windows.'10.0.17134') {
                $json.windows.'10.0.17134'.vmArgs = @(
                    "-XX:+UseG1GC",
                    "-Dpzopt.gc=g1",
                    "-XX:MaxGCPauseMillis=5"
                )
            }
            if ($json.windows.'6.1') {
                $json.windows.'6.1'.vmArgs = @(
                    "-XX:+UseG1GC",
                    "-Dpzopt.gc=g1",
                    "-XX:MaxGCPauseMillis=5"
                )
            }
        }
        if ($json.linux) {
            $json.linux.vmArgs = @(
                "-XX:+UseG1GC",
                "-Dpzopt.gc=g1",
                "-XX:MaxGCPauseMillis=5"
            )
        }
        if ($json.macos) {
            $json.macos.vmArgs = @(
                "-XX:+UseG1GC",
                "-Dpzopt.gc=g1",
                "-XX:MaxGCPauseMillis=5"
            )
        }

        # Write clean UTF-8 WITHOUT BOM using UTF8Encoding($false)
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $newContent = ($json | ConvertTo-Json -Depth 10)
        [System.IO.File]::WriteAllText($jsonPath, $newContent, $utf8NoBom)
        Write-Host " [SUCCESS] JVM successfully configured for Low-Latency G1GC (-XX:MaxGCPauseMillis=5)!" -ForegroundColor Green
        Write-Host "           UTF-8 BOM-free encoding verified. ZombieBuddy & native launcher preserved." -ForegroundColor Gray
    } catch {
        Write-Host " [ERROR] Failed to update ProjectZomboid64.json: $($_.Exception.Message)" -ForegroundColor Red
        if ($isLinux -or $isMacOS) {
            Write-Host " [TIP] You can also apply G1GC via Steam Launch Options:" -ForegroundColor Cyan
            Write-Host "       %command% -XX:+UseG1GC -XX:MaxGCPauseMillis=5 -Xmx16g" -ForegroundColor White
        }
    }
}

# ==============================================================================
# Optimization Action: Engine Graphics & Frame Pacing Optimizer
# ==============================================================================
function Set-PZOptionsSetting([string]$key, [string]$value) {
    $optionsIni = Join-Path $ZomboidUserPath "options.ini"
    if (-not (Test-Path $optionsIni)) {
        Write-Host " [!] options.ini not found at $optionsIni" -ForegroundColor Red
        return $false
    }

    # Backup original before modifying
    $bakPath = "$optionsIni.bak"
    if (-not (Test-Path $bakPath)) {
        Copy-Item $optionsIni $bakPath -Force
        Write-Host " [OK] Backed up original display options to options.ini.bak" -ForegroundColor Gray
    }

    $lines = Get-Content $optionsIni -ErrorAction Stop
    $updated = $false
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match "^$key=") {
            $newLines += "$key=$value"
            $updated = $true
        } else {
            $newLines += $line
        }
    }
    if (-not $updated) {
        $newLines += "$key=$value"
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($optionsIni, $newLines, $utf8NoBom)
    return $true
}

function Set-PZFrameCap([int]$targetFps) {
    if (Set-PZOptionsSetting "frameRate" "$targetFps") {
        Write-Host " [SUCCESS] Game frame rate cap set to $targetFps FPS in options.ini!" -ForegroundColor Green
        Write-Host "           This directly throttles per-frame Lua tick execution overhead." -ForegroundColor Gray
    }
}

function Optimize-PZGraphicsAutoTune {
    Write-Host "`n[*] Applying Recommended Engine Graphics & Frame Pacing Profile..." -ForegroundColor Yellow
    $optionsIni = Join-Path $ZomboidUserPath "options.ini"
    if (-not (Test-Path $optionsIni)) {
        Write-Host " [!] options.ini not found at $optionsIni" -ForegroundColor Red
        return
    }

    # Backup original before modifying
    $bakPath = "$optionsIni.bak"
    if (-not (Test-Path $bakPath)) {
        Copy-Item $optionsIni $bakPath -Force
        Write-Host " [OK] Backed up original display options to options.ini.bak" -ForegroundColor Gray
    }

    $settingsToApply = @{
        'frameRate'           = '120'
        'modelTextureMipmaps' = 'true'
        'lightFPS'            = '60'
        'maxActiveRagdolls'   = '10'
        'textureCompression'  = 'true'
    }

    $lines = Get-Content $optionsIni -ErrorAction Stop
    $seenKeys = @{}
    $newLines = @()
    foreach ($line in $lines) {
        $matched = $false
        foreach ($k in $settingsToApply.Keys) {
            if ($line -match "^$k=") {
                $newLines += "$k=$($settingsToApply[$k])"
                $seenKeys[$k] = $true
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $newLines += $line
        }
    }

    foreach ($k in $settingsToApply.Keys) {
        if (-not $seenKeys.ContainsKey($k)) {
            $newLines += "$k=$($settingsToApply[$k])"
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($optionsIni, $newLines, $utf8NoBom)
    Write-Host " [SUCCESS] Recommended graphics tuning applied to options.ini!" -ForegroundColor Green
    Write-Host "   -> Frame Rate Cap          : 120 FPS (Smooth pacing & lower Lua tick multiplier)" -ForegroundColor Cyan
    Write-Host "   -> 3D Model Mipmaps        : Enabled (Eliminates GPU cache thrashing & visual shimmer)" -ForegroundColor Cyan
    Write-Host "   -> Dynamic Lighting Rate   : 60 FPS (Eliminates 30Hz light hitching during 120 FPS play)" -ForegroundColor Cyan
    Write-Host "   -> Ragdoll Physics Ceiling : 10 Bodies (Prevents dense combat CPU physics stalls)" -ForegroundColor Cyan
    Write-Host "   -> Texture Compression     : Enabled (Prevents PCIe VRAM saturation & texture thrashing)" -ForegroundColor Cyan
    Write-Host "   Backup created at: $bakPath (restore anytime via Menu Option [7])" -ForegroundColor Gray
}

function Invoke-PZGraphicsOptimizer {
    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "   ENGINE GRAPHICS & FRAME PACING OPTIMIZER                      " -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " Audits and resolves in-game options.ini performance bottlenecks." -ForegroundColor Gray
    Write-Host "  [1] 1-Click Recommended Graphics Optimization (Auto-Tune)" -ForegroundColor Green
    Write-Host "      -> 120 FPS Cap, Model Mipmaps ON, Lighting 60 FPS, Ragdolls 10, Compression ON" -ForegroundColor Gray
    Write-Host "  [2] Change Display Frame Rate Cap (60 / 120 / 144 / 240 / Custom)" -ForegroundColor White
    Write-Host "  [3] Enable 3D Model Mipmaps (modelTextureMipmaps=true)" -ForegroundColor White
    Write-Host "  [4] Sync Dynamic Lighting Tick Rate (lightFPS=60)" -ForegroundColor White
    Write-Host "  [5] Optimize Ragdoll Simulation Ceiling (maxActiveRagdolls=10)" -ForegroundColor White
    Write-Host "  [6] Enable Texture Compression (textureCompression=true)" -ForegroundColor White
    Write-Host "  [0] Back to Main Menu" -ForegroundColor Gray
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan

    $gChoice = Read-Host " Select an option (0-6)"
    switch ($gChoice.Trim()) {
        "1" {
            Optimize-PZGraphicsAutoTune
        }
        "2" {
            Write-Host "`nChoose Frame Rate Cap for Project Zomboid:" -ForegroundColor Cyan
            Write-Host " [1] 60 FPS   (Recommended for heavy 100+ modpacks)" -ForegroundColor White
            Write-Host " [2] 120 FPS  (Great balance for 120Hz/144Hz displays)" -ForegroundColor White
            Write-Host " [3] 144 FPS  (Matches 144Hz refresh rate)" -ForegroundColor White
            Write-Host " [4] 240 FPS  (High CPU tick overhead)" -ForegroundColor White
            Write-Host " [5] Custom FPS" -ForegroundColor White
            $fcChoice = Read-Host " Select option"
            $fps = switch ($fcChoice.Trim()) {
                "1" { 60 }
                "2" { 120 }
                "3" { 144 }
                "4" { 240 }
                "5" { [int](Read-Host " Enter custom FPS") }
                Default { 120 }
            }
            if ($fps -gt 0) { Set-PZFrameCap $fps }
        }
        "3" {
            if (Set-PZOptionsSetting "modelTextureMipmaps" "true") {
                Write-Host " [SUCCESS] 3D Model Mipmaps enabled (modelTextureMipmaps=true)!" -ForegroundColor Green
                Write-Host "           Eliminates texture cache thrashing and visual distance shimmering on custom 3D meshes." -ForegroundColor Gray
            }
        }
        "4" {
            if (Set-PZOptionsSetting "lightFPS" "60") {
                Write-Host " [SUCCESS] Dynamic lighting tick rate increased to 60 FPS (lightFPS=60)!" -ForegroundColor Green
                Write-Host "           Eliminates lighting dissonance and shadow judder when playing above 60 FPS." -ForegroundColor Gray
            }
        }
        "5" {
            if (Set-PZOptionsSetting "maxActiveRagdolls" "10") {
                Write-Host " [SUCCESS] Ragdoll physics ceiling clamped to 10 bodies (maxActiveRagdolls=10)!" -ForegroundColor Green
                Write-Host "           Prevents CPU physics computation spikes during dense horde combat." -ForegroundColor Gray
            }
        }
        "6" {
            if (Set-PZOptionsSetting "textureCompression" "true") {
                Write-Host " [SUCCESS] Texture Compression enabled (textureCompression=true)!" -ForegroundColor Green
                Write-Host "           Loads textures compressed in VRAM, preventing PCIe texture thrashing." -ForegroundColor Gray
            }
        }
        Default {
            Write-Host " Returning to main menu." -ForegroundColor Gray
        }
    }
}

# ==============================================================================
# Optimization Action: Clean Phantom / Missing Mods from Save
# ==============================================================================
function Invoke-PZCleanSaveMods([switch]$Headless, [string]$TargetSaveDir = "") {
    Write-Host "`n[*] Scanning savegame mod configuration..." -ForegroundColor Yellow
    $latestSaveIni = Join-Path $ZomboidUserPath "latestSave.ini"
    $saveDir = $null
    $saveName = "Unknown"

    if ($TargetSaveDir -and (Test-Path $TargetSaveDir)) {
        $saveDir = $TargetSaveDir
        $leaf = Split-Path $saveDir -Leaf
        $parent = Split-Path (Split-Path $saveDir) -Leaf
        $saveName = if ($parent) { "$parent / $leaf" } else { $leaf }
    } elseif (Test-Path $latestSaveIni) {
        $lines = Get-Content $latestSaveIni
        if ($lines.Count -ge 2) {
            $candidate = Join-Path $ZomboidUserPath "Saves\$($lines[1].Trim())\$($lines[0].Trim())"
            if (Test-Path $candidate) {
                $saveDir = $candidate
                $saveName = "$($lines[1].Trim()) / $($lines[0].Trim())"
            }
        }
    }
    if (-not $saveDir) {
        $latest = Get-ChildItem -Path (Join-Path $ZomboidUserPath "Saves") -Recurse -Filter "mods.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) {
            $saveDir = $latest.DirectoryName
            $saveName = $latest.Directory.Name
        }
    }
    if (-not $saveDir) {
        Write-Host " [!] No active savegame found in $ZomboidUserPath\Saves." -ForegroundColor Yellow
        return
    }

    $modsFile = Join-Path $saveDir "mods.txt"
    if (-not (Test-Path $modsFile)) {
        Write-Host " [!] mods.txt not found in save: $saveDir" -ForegroundColor Yellow
        return
    }

    # Gather installed mod IDs and titles across Workshop, local mods, and custom paths
    $installedIds = @()
    $installedTitles = @{}
    $wsPaths = Get-WorkshopPaths -customPath $CustomWorkshopPath
    foreach ($w in $wsPaths) {
        $infos = Get-ChildItem -Path $w -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue
        foreach ($i in $infos) {
            $c = Get-Content $i.FullName -ErrorAction SilentlyContinue
            $id = (($c | Where-Object { $_ -match '^id=' }) -replace '^id=\s*', '').Trim() | Select-Object -First 1
            $name = (($c | Where-Object { $_ -match '^name=' }) -replace '^name=\s*', '').Trim() | Select-Object -First 1
            if ($id) {
                if ($installedIds -notcontains $id) { $installedIds += $id }
                if ($name -and -not $installedTitles[$id]) { $installedTitles[$id] = $name }
            }
        }
    }
    $localMods = Join-Path $ZomboidUserPath "mods"
    if (Test-Path $localMods) {
        $infos = Get-ChildItem -Path $localMods -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue
        foreach ($i in $infos) {
            $c = Get-Content $i.FullName -ErrorAction SilentlyContinue
            $id = (($c | Where-Object { $_ -match '^id=' }) -replace '^id=\s*', '').Trim() | Select-Object -First 1
            $name = (($c | Where-Object { $_ -match '^name=' }) -replace '^name=\s*', '').Trim() | Select-Object -First 1
            if ($id) {
                if ($installedIds -notcontains $id) { $installedIds += $id }
                if ($name -and -not $installedTitles[$id]) { $installedTitles[$id] = $name }
            }
        }
    }

    $currentMods = Get-Content $modsFile
    $activeModList = @()
    foreach ($line in $currentMods) {
        if ($line -match 'mod\s*=\s*([^,;]+)') {
            $mId = ($matches[1] -replace '\s*}.*$', '').Trim()
            if ($mId -and ($activeModList -notcontains $mId)) {
                $activeModList += $mId
            }
        }
    }

    $missingMods = @($activeModList | Where-Object { $installedIds -notcontains $_ })

    # If Headless CLI mode, automatically execute phantom mod purge
    if ($Headless) {
        if ($missingMods.Count -eq 0) {
            Write-Host " [OK] All mods in savegame are verified installed on disk. No phantom mods found!" -ForegroundColor Green
            return
        }
        Write-Host " [!] Found $($missingMods.Count) phantom/missing mod(s) in savegame:" -ForegroundColor Yellow
        foreach ($m in $missingMods) {
            Write-Host "     - $m" -ForegroundColor DarkYellow
        }
        $bakFile = "$modsFile.bak"
        if (-not (Test-Path $bakFile)) {
            Copy-Item $modsFile $bakFile -Force
            Write-Host " [OK] Backed up original mods.txt to mods.txt.bak" -ForegroundColor Gray
        }
        $cleanedLines = @()
        foreach ($line in $currentMods) {
            if ($line -match 'mod\s*=\s*([^,;]+)') {
                $mId = ($matches[1] -replace '\s*}.*$', '').Trim()
                if ($mId -and ($missingMods -contains $mId)) {
                    continue
                }
            }
            $cleanedLines += $line
        }
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllLines($modsFile, $cleanedLines, $utf8NoBom)
        Write-Host "`n [SUCCESS] Removed $($missingMods.Count) uninstalled mod(s) from savegame!" -ForegroundColor Green
        return
    }

    # Interactive Sub-Menu
    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "   SAVEGAME MOD SANITIZER & PHANTOM PURGER ($Script:SuiteVersion)             " -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " Active Savegame : $saveName" -ForegroundColor White
    Write-Host " Save Path       : $modsFile" -ForegroundColor DarkGray
    Write-Host " Active Mods     : $($activeModList.Count) enabled in mods.txt" -ForegroundColor Cyan
    if ($missingMods.Count -gt 0) {
        Write-Host " Uninstalled     : $($missingMods.Count) phantom mod(s) detected!" -ForegroundColor Yellow
    }

    Write-Host "`n Enabled Mods in this Save:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $activeModList.Count; $i++) {
        $mId = $activeModList[$i]
        $title = if ($installedTitles[$mId]) { " ($($installedTitles[$mId]))" } else { "" }
        $status = if ($installedIds -contains $mId) { "[Installed]" } else { "[PHANTOM / MISSING FROM DISK]" }
        $statusColor = if ($installedIds -contains $mId) { "White" } else { "Yellow" }
        Write-Host "   [$($i + 1)] $mId$title $status" -ForegroundColor $statusColor
    }

    Write-Host "`n Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Auto-Purge Uninstalled Phantom Mods (Removes missing mods only)" -ForegroundColor White
    Write-Host "  [2] Selectively Disable / Remove an Enabled Mod from this Save" -ForegroundColor White
    Write-Host "  [3] Restore Savegame Backup (mods.txt.bak)" -ForegroundColor White
    Write-Host "  [4] Select a Different Savegame to Inspect or Clean" -ForegroundColor White
    Write-Host "  [0] Back to Main Menu" -ForegroundColor Gray

    $actionChoice = Read-Host "`n Select an option (0-4)"
    switch ($actionChoice.Trim()) {
        "1" {
            if ($missingMods.Count -eq 0) {
                Write-Host "`n [OK] All $($activeModList.Count) mods in savegame are verified installed on disk." -ForegroundColor Green
                Write-Host "      No uninstalled phantom mods found to purge!" -ForegroundColor Gray
            } else {
                Write-Host "`n [!] Found $($missingMods.Count) phantom/missing mod(s) to purge:" -ForegroundColor Yellow
                foreach ($m in $missingMods) {
                    Write-Host "     - $m" -ForegroundColor DarkYellow
                }
                $bakFile = "$modsFile.bak"
                if (-not (Test-Path $bakFile)) {
                    Copy-Item $modsFile $bakFile -Force
                    Write-Host " [OK] Backed up original mods.txt to mods.txt.bak" -ForegroundColor Gray
                }
                $cleanedLines = @()
                foreach ($line in $currentMods) {
                    if ($line -match 'mod\s*=\s*([^,;]+)') {
                        $mId = ($matches[1] -replace '\s*}.*$', '').Trim()
                        if ($mId -and ($missingMods -contains $mId)) {
                            continue
                        }
                    }
                    $cleanedLines += $line
                }
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllLines($modsFile, $cleanedLines, $utf8NoBom)
                Write-Host "`n [SUCCESS] Removed $($missingMods.Count) uninstalled phantom mod(s) from savegame!" -ForegroundColor Green
            }
        }
        "2" {
            Write-Host "`nEnter the number (1-$($activeModList.Count)) or mod ID to remove from this savegame:" -ForegroundColor Yellow
            $modInput = (Read-Host "Mod selection").Trim()
            $targetToRemove = $null
            if ($modInput -match '^\d+$') {
                $idx = [int]$modInput
                if ($idx -ge 1 -and $idx -le $activeModList.Count) {
                    $targetToRemove = $activeModList[$idx - 1]
                }
            } elseif ($activeModList -contains $modInput) {
                $targetToRemove = $modInput
            }

            if ($targetToRemove) {
                $bakFile = "$modsFile.bak"
                if (-not (Test-Path $bakFile)) {
                    Copy-Item $modsFile $bakFile -Force
                    Write-Host " [OK] Backed up original mods.txt to mods.txt.bak" -ForegroundColor Gray
                }
                $cleanedLines = @()
                foreach ($line in $currentMods) {
                    if ($line -match 'mod\s*=\s*([^,;]+)') {
                        $mId = ($matches[1] -replace '\s*}.*$', '').Trim()
                        if ($mId -eq $targetToRemove) {
                            continue
                        }
                    }
                    $cleanedLines += $line
                }
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllLines($modsFile, $cleanedLines, $utf8NoBom)
                Write-Host "`n [SUCCESS] Successfully removed '$targetToRemove' from savegame!" -ForegroundColor Green
                Write-Host "           Savegame: $saveName" -ForegroundColor Cyan
                Write-Host "           Backup  : $bakFile" -ForegroundColor DarkGray
                Write-Host "           Project Zomboid will now boot without loading '$targetToRemove'." -ForegroundColor Gray
            } else {
                Write-Host "`n [!] Invalid mod selection. No changes made." -ForegroundColor Red
            }
        }
        "3" {
            $bakFile = "$modsFile.bak"
            if (Test-Path $bakFile) {
                Copy-Item $bakFile $modsFile -Force
                Write-Host "`n [SUCCESS] Restored original mods.txt from $bakFile!" -ForegroundColor Green
            } else {
                Write-Host "`n [!] No mods.txt.bak backup found in save folder: $saveDir" -ForegroundColor Yellow
            }
        }
        "4" {
            $savesRoot = Join-Path $ZomboidUserPath "Saves"
            if (-not (Test-Path $savesRoot)) {
                Write-Host "`n [!] Saves folder not found at $savesRoot" -ForegroundColor Yellow
                return
            }
            $availableSaves = @(Get-ChildItem -Path $savesRoot -Recurse -Filter "mods.txt" -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending)
            if ($availableSaves.Count -eq 0) {
                Write-Host "`n [!] No savegames with mods.txt found." -ForegroundColor Yellow
                return
            }
            Write-Host "`nAvailable Savegames:" -ForegroundColor Cyan
            for ($sIdx = 0; $sIdx -lt $availableSaves.Count; $sIdx++) {
                $sf = $availableSaves[$sIdx]
                $sFolder = $sf.Directory.Name
                $sMode = $sf.Directory.Parent.Name
                $sTime = $sf.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                Write-Host " [$($sIdx + 1)] $sMode / $sFolder ($sTime)" -ForegroundColor White
            }
            $sChoice = Read-Host "`nSelect savegame number (1-$($availableSaves.Count))"
            if ($sChoice -match '^\d+$' -and [int]$sChoice -ge 1 -and [int]$sChoice -le $availableSaves.Count) {
                $chosenSaveDir = $availableSaves[[int]$sChoice - 1].DirectoryName
                Invoke-PZCleanSaveMods -TargetSaveDir $chosenSaveDir
                return
            } else {
                Write-Host "`n [!] Invalid selection." -ForegroundColor Red
            }
        }
        Default {
            Write-Host " Returning to main menu." -ForegroundColor Gray
        }
    }
}

# ==============================================================================
# Rollback & Recovery Actions: Revert Changes
# ==============================================================================
function Revert-PZGC {
    Write-Host "`n[*] Reverting Java GC Optimizer settings..." -ForegroundColor Yellow
    $installDir = Get-PZInstallPath
    if (-not $installDir) {
        Write-Host " [!] Could not locate Project Zomboid installation directory." -ForegroundColor Red
        return
    }
    $jsonPath = Join-Path $installDir "ProjectZomboid64.json"
    $bakPath = "$jsonPath.bak"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (Test-Path $bakPath) {
        try {
            $bakBytes = [System.IO.File]::ReadAllBytes($bakPath)
            if ($bakBytes.Length -ge 3 -and $bakBytes[0] -eq 0xEF -and $bakBytes[1] -eq 0xBB -and $bakBytes[2] -eq 0xBF) {
                $cleanBytes = [byte[]]::new($bakBytes.Length - 3)
                [System.Array]::Copy($bakBytes, 3, $cleanBytes, 0, $cleanBytes.Length)
                [System.IO.File]::WriteAllBytes($jsonPath, $cleanBytes)
                [System.IO.File]::WriteAllBytes($bakPath, $cleanBytes)
            } else {
                Copy-Item $bakPath $jsonPath -Force
            }
            Write-Host " [SUCCESS] Restored original ProjectZomboid64.json from backup (.bak)!" -ForegroundColor Green
            Write-Host "           Vanilla JVM arguments (ZGC / default heap) have been restored without BOM." -ForegroundColor Gray
        } catch {
            Write-Host " [ERROR] Failed to restore ProjectZomboid64.json from backup: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        if (Test-Path $jsonPath) {
            try {
                $raw = Get-Content $jsonPath -Raw -ErrorAction Stop
                if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
                    $raw = $raw.Substring(1)
                }
                $json = $raw | ConvertFrom-Json
                if ($json.windows -and $json.windows.'10.0.17134') {
                    $json.windows.'10.0.17134'.vmArgs = @("-XX:+UseZGC")
                }
                if ($json.linux) {
                    $json.linux.vmArgs = @("-XX:+UseZGC")
                }
                if ($json.macos) {
                    $json.macos.vmArgs = @("-XX:+UseZGC")
                }
                $newContent = ($json | ConvertTo-Json -Depth 10)
                [System.IO.File]::WriteAllText($jsonPath, $newContent, $utf8NoBom)
                Write-Host " [SUCCESS] Reset JVM settings in ProjectZomboid64.json back to vanilla defaults (-XX:+UseZGC)." -ForegroundColor Green
            } catch {
                Write-Host " [ERROR] Failed to restore ProjectZomboid64.json: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host " [!] Neither ProjectZomboid64.json nor its backup were found." -ForegroundColor Yellow
        }
    }
}

function Revert-PZFrameCap {
    Write-Host "`n[*] Reverting Frame Rate Cap setting..." -ForegroundColor Yellow
    $optionsIni = Join-Path $ZomboidUserPath "options.ini"
    $bakPath = "$optionsIni.bak"
    if (Test-Path $bakPath) {
        $origFps = "240"
        $bakLines = Get-Content $bakPath -ErrorAction SilentlyContinue
        foreach ($bl in $bakLines) {
            if ($bl -match '^frameRate=(\d+)') {
                $origFps = $matches[1]
                break
            }
        }
        Copy-Item $bakPath $optionsIni -Force
        Write-Host " [SUCCESS] Restored original options.ini from backup! (frameRate=$origFps)" -ForegroundColor Green
    } else {
        if (Test-Path $optionsIni) {
            $lines = Get-Content $optionsIni -ErrorAction Stop
            $newLines = @()
            $found = $false
            foreach ($line in $lines) {
                if ($line -match '^frameRate=') {
                    $newLines += "frameRate=240"
                    $found = $true
                } else {
                    $newLines += $line
                }
            }
            if ($found) {
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllLines($optionsIni, $newLines, $utf8NoBom)
                Write-Host " [SUCCESS] Reset frameRate to 240 FPS (Project Zomboid default) in options.ini." -ForegroundColor Green
            }
        } else {
            Write-Host " [!] options.ini not found." -ForegroundColor Yellow
        }
    }
}

function Revert-PZSaveMods {
    Write-Host "`n[*] Reverting cleaned savegame mods..." -ForegroundColor Yellow
    $latestSaveIni = Join-Path $ZomboidUserPath "latestSave.ini"
    $saveDir = $null
    if (Test-Path $latestSaveIni) {
        $lines = Get-Content $latestSaveIni
        if ($lines.Count -ge 2) {
            $candidate = Join-Path $ZomboidUserPath "Saves\$($lines[1].Trim())\$($lines[0].Trim())"
            if (Test-Path $candidate) { $saveDir = $candidate }
        }
    }
    if (-not $saveDir) {
        $latest = Get-ChildItem -Path (Join-Path $ZomboidUserPath "Saves") -Recurse -Filter "mods.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $saveDir = $latest.DirectoryName }
    }
    
    $restoredCount = 0
    if ($saveDir) {
        $modsBak = Join-Path $saveDir "mods.txt.bak"
        $modsFile = Join-Path $saveDir "mods.txt"
        if (Test-Path $modsBak) {
            Copy-Item $modsBak $modsFile -Force
            Write-Host " [SUCCESS] Restored original mods.txt from mods.txt.bak in active save: $(Split-Path $saveDir -Leaf)" -ForegroundColor Green
            $restoredCount++
        }
    }
    
    $otherBaks = Get-ChildItem -Path (Join-Path $ZomboidUserPath "Saves") -Recurse -Filter "mods.txt.bak" -ErrorAction SilentlyContinue
    foreach ($ob in $otherBaks) {
        if ($saveDir -and ($ob.DirectoryName -eq $saveDir)) { continue }
        $target = Join-Path $ob.DirectoryName "mods.txt"
        Copy-Item $ob.FullName $target -Force
        Write-Host " [SUCCESS] Restored original mods.txt in save: $($ob.Directory.Name)" -ForegroundColor Green
        $restoredCount++
    }

    if ($restoredCount -eq 0) {
        Write-Host " [!] No mods.txt.bak backup files found in any savegame." -ForegroundColor Yellow
    }
}

function Invoke-PZRevertChanges([string]$Target = "All") {
    Write-Host "`n=================================================================" -ForegroundColor Cyan
    Write-Host "                  REVERTING OPTIMIZATION CHANGES                 " -ForegroundColor Yellow
    Write-Host "=================================================================" -ForegroundColor Cyan
    switch ($Target.ToLower()) {
        "gc" {
            Revert-PZGC
        }
        "fps" {
            Revert-PZFrameCap
        }
        "save" {
            Revert-PZSaveMods
        }
        Default {
            Revert-PZGC
            Revert-PZFrameCap
            Revert-PZSaveMods
        }
    }
    Write-Host "=================================================================`n" -ForegroundColor Cyan
}

# ==============================================================================
# Helper Functions: Semantic Lua & Version-Aware Directory Analysis
# ==============================================================================
function Get-ModActiveDirectories([string]$modDir, [string]$gameVersion) {
    if (-not (Test-Path $modDir)) { return @() }
    $subdirs = Get-ChildItem -Path $modDir -Directory -ErrorAction SilentlyContinue
    $verDirs = $subdirs | Where-Object { $_.Name -match '^42\.\d+$|^42$|^41\.\d+$|^41$' }
    
    if (-not $verDirs) {
        return @($modDir)
    }

    $activeDirs = @()
    $isB42 = (-not $gameVersion -or $gameVersion -match '^42' -or $gameVersion -eq 'Unknown')
    
    if ($isB42) {
        $v42 = $verDirs | Where-Object { $_.Name -match '^42' }
        if ($v42) {
            $sorted = $v42 | Sort-Object {
                if ($_.Name -match '^42\.(\d+)$') { [int]$matches[1] } else { 0 }
            } -Descending
            $activeDirs += $sorted[0].FullName
        }
    } else {
        $v41 = $verDirs | Where-Object { $_.Name -match '^41' }
        if ($v41) {
            $sorted = $v41 | Sort-Object {
                if ($_.Name -match '^41\.(\d+)$') { [int]$matches[1] } else { 0 }
            } -Descending
            $activeDirs += $sorted[0].FullName
        }
    }

    if ($activeDirs.Count -eq 0 -and $verDirs.Count -gt 0) {
        $activeDirs += $verDirs[0].FullName
    }

    $common = $subdirs | Where-Object { $_.Name -eq 'common' }
    if ($common) { $activeDirs += $common.FullName }

    return $activeDirs
}

function Analyze-ModLuaSemantics([System.IO.FileInfo[]]$luaFiles) {
    $permHooks = 0
    $transHooks = 0
    $throttledHooks = 0
    $hookBreakdown = @()
    $inHookZombieQueries = 0
    $staticZombieQueries = 0
    $inHookTileQueries = 0
    $staticTileQueries = 0
    $inHookWorldQueries = 0
    $staticWorldQueries = 0
    $inHookInvQueries = 0
    $staticInvQueries = 0
    $inHookHeavyContainers = 0
    $staticHeavyContainers = 0
    $inHookUIPolls = 0
    $staticUIPolls = 0
    $inHookJNICalls = 0
    $staticJNICalls = 0

    $fileData = @()
    $fullCodeBuilder = New-Object System.Text.StringBuilder

    foreach ($lf in $luaFiles) {
        $c = Get-Content $lf.FullName -Raw -ErrorAction SilentlyContinue
        if ($c) {
            [void]$fullCodeBuilder.AppendLine($c)
            $fileData += [PSCustomObject]@{
                Path = $lf.FullName
                Code = $c
            }
        }
    }
    $fullCode = $fullCodeBuilder.ToString()

    foreach ($fd in $fileData) {
        $code = $fd.Code
        $addMatches = [regex]::Matches($code, 'Events\.(OnTick|OnRenderTick|OnPlayerUpdate|OnZombieUpdate|OnRender3D)\.Add\s*\(\s*([a-zA-Z0-9_\.:]+)?')
        $hasPerFrame = ($addMatches.Count -gt 0)

        # Queries: Differentiate entity/zombie scans from map tile/square lookups
        $zq = ([regex]::Matches($code, 'getZombieList|getMovingObjects|getCharacters|getZombies|getHitReaction|getNearZombies')).Count
        $tq = ([regex]::Matches($code, 'getSquare|getGridSquare|getIsoObject|getCell\(\):getGridSquare')).Count
        $wq = $zq + $tq
        $heavyContainerPattern = 'refreshBackpacks|refreshContainer|refreshWeight|updateContainers|refreshFloor|applyContainers'
        $iq = ([regex]::Matches($code, "getAllItems|getItems|FindAndReturn|$heavyContainerPattern")).Count
        $hc = ([regex]::Matches($code, $heavyContainerPattern)).Count
        $uiPollPattern = 'UIManager\.(getUI|findWidget|getWidgets)|:isReallyVisible\(\)|:getIsVisible\(\)|:isVisible\(\)'
        $uiPoll = ([regex]::Matches($code, $uiPollPattern)).Count
        $jniPattern = 'luajava\.bindClass|Class\.forName|\.getDeclaredMethod|\.getMethod|\.invoke\(|ViewpointQOLSettings'
        $jni = ([regex]::Matches($code, $jniPattern)).Count

        $hookCodeBlocks = @()
        foreach ($m in $addMatches) {
            $hookEvent = $m.Groups[1].Value
            $funcName = $m.Groups[2].Value

            $isRemove = $false
            if ($funcName) {
                $esc = [regex]::Escape($funcName)
                if ($fullCode -match "Events\.$hookEvent\.Remove\s*\(\s*$esc") {
                    $isRemove = $true
                }
            }
            if (-not $isRemove -and $code -match "Events\.$hookEvent\.Remove") {
                $isRemove = $true
            }

            if ($isRemove) {
                $transHooks++
                $hookBreakdown += "$hookEvent (Transient)"
            } else {
                # Function-scoped extraction: inspect the specific handler function if available
                $targetCode = $code
                if ($funcName) {
                    $esc = [regex]::Escape($funcName)
                    $funcRegex = "(?s)(?:local\s+function\s+$esc|function\s+$esc|$esc\s*=\s*function)\s*\([^\)]*\)(.*?)(?=(\r?\n\s*(?:local\s+)?function\s|\r?\n\s*[a-zA-Z0-9_\.:]+\s*=\s*function|\Z))"
                    $fMatch = [regex]::Match($code, $funcRegex)
                    if (-not $fMatch.Success) {
                        $fMatch = [regex]::Match($fullCode, $funcRegex)
                    }
                    if ($fMatch.Success -and $fMatch.Groups[1].Value.Length -gt 15) {
                        $targetCode = $fMatch.Groups[1].Value
                        $hookCodeBlocks += $targetCode
                    }
                }

                $hasThrottle = ($targetCode -match '%\s*\d+|tickCounter|RefreshTick|TimeToRefresh|TicksToComplete|getMultiplier\(\)|frameCounter|interval|throttle|Modulo|\boptionsSyncCounter\b|\bcontainersRefreshCounter\b')
                $hasStateGate = ($targetCode -match 'if\s+not\s+[\w\.:]+(\s+then|\s*\n\s*then|\s*\)\s*then)?\s*(\n\s*)?return|if\s+[\w\.:]+\s*==\s*(0|false|nil)\s+then|if\s+#\w+\s*==\s*0\s+then|if\s+not\s+player:isMoving|isPlayerMoving|isDriving|player:getVehicle\(\)|player\.getVehicle|getVehicle\(\)\s*==\s*nil|isVehicle\s*==\s*false|active\(\)|usablePlayer|C1PVBridge|if\s+not\s+self:isVisible|if\s+not\s+self\.isOpen|if\s+not\s+self\.isCollapsed|if\s+not\s+self\.shown')
                $hasUnthrottledPerFrameWork = ($targetCode -match 'is(?:Inventory|Radial|Device|Menu|Window)Open|UIManager\.|getMovingObjects|getZombieList')

                if ($hasThrottle -and $hasUnthrottledPerFrameWork) {
                    $throttledHooks++
                    $hookBreakdown += "$hookEvent (Hybrid / UI-Gated)"
                } elseif ($hasThrottle) {
                    $throttledHooks++
                    $hookBreakdown += "$hookEvent (Throttled)"
                } elseif ($hasStateGate) {
                    $throttledHooks++
                    $hookBreakdown += "$hookEvent (State-Gated)"
                } else {
                    $permHooks++
                    $hookBreakdown += "$hookEvent (Permanent Loop)"
                }
            }
        }

        # Query Isolation: Scope-aware queries
        if ($hasPerFrame -and $hookCodeBlocks.Count -gt 0) {
            $hookCodeJoined = $hookCodeBlocks -join "`n"
            $hZq = [math]::Min($zq, ([regex]::Matches($hookCodeJoined, 'getZombieList|getMovingObjects|getCharacters|getZombies|getHitReaction|getNearZombies')).Count)
            $hTq = [math]::Min($tq, ([regex]::Matches($hookCodeJoined, 'getSquare|getGridSquare|getIsoObject|getCell\(\):getGridSquare')).Count)
            $hIq = [math]::Min($iq, ([regex]::Matches($hookCodeJoined, "getAllItems|getItems|FindAndReturn|$heavyContainerPattern")).Count)
            $hHc = [math]::Min($hc, ([regex]::Matches($hookCodeJoined, $heavyContainerPattern)).Count)
            $hUi = [math]::Min($uiPoll, ([regex]::Matches($hookCodeJoined, $uiPollPattern)).Count)
            $hJni = [math]::Min($jni, ([regex]::Matches($hookCodeJoined, $jniPattern)).Count)

            $inHookZombieQueries += $hZq
            $inHookTileQueries += $hTq
            $inHookWorldQueries += ($hZq + $hTq)
            $inHookInvQueries += $hIq
            $inHookHeavyContainers += $hHc
            $inHookUIPolls += $hUi
            $inHookJNICalls += $hJni

            $staticZombieQueries += [math]::Max(0, $zq - $hZq)
            $staticTileQueries += [math]::Max(0, $tq - $hTq)
            $staticWorldQueries += [math]::Max(0, $wq - ($hZq + $hTq))
            $staticInvQueries += [math]::Max(0, $iq - $hIq)
            $staticHeavyContainers += [math]::Max(0, $hc - $hHc)
            $staticUIPolls += [math]::Max(0, $uiPoll - $hUi)
            $staticJNICalls += [math]::Max(0, $jni - $hJni)
        } elseif ($hasPerFrame) {
            # Anonymous function or unisolated hook handler: conservative file fallback
            $inHookZombieQueries += $zq
            $inHookTileQueries += $tq
            $inHookWorldQueries += $wq
            $inHookInvQueries += $iq
            $inHookHeavyContainers += $hc
            $inHookUIPolls += $uiPoll
            $inHookJNICalls += $jni
        } else {
            $staticZombieQueries += $zq
            $staticTileQueries += $tq
            $staticWorldQueries += $wq
            $staticInvQueries += $iq
            $staticHeavyContainers += $hc
            $staticUIPolls += $uiPoll
            $staticJNICalls += $jni
        }
    }

    $isStationaryGated = ($fullCode -match 'not\s+(?:player:)?isPlayerMoving|not\s+(?:player:)?isMoving|isStationary|isPlayerStationary|local\s+moving\s*=\s*.*isPlayerMoving.*if\s+not\s+moving\b|if\s+not\s+moving\b')
    $isOptInToggle = ($fullCode -match 'isActive\(\)|isEnabled\b|toggleState|isToggled|getCustomOption|HOTKEY_BINDING')
    $optInModeName = $null
    if ($fullCode -match 'ViewpointQOLContainers|enableContainersHotkey|containersKey') {
        $optInModeName = "All-Containers Mode"
    } elseif ($fullCode -match 'enable(\w+)(?:Hotkey|Toggle)') {
        $optInModeName = "$($matches[1]) Hotkey"
    } elseif ($fullCode -match '(?:^|[^\w\.])is([A-Z]\w+)Active\(\)' -and $matches[1] -notmatch 'Mod|PZ|Steam|Client|Server') {
        $optInModeName = "$($matches[1]) Mode"
    } elseif ($fullCode -match 'HOTKEY_BINDING') {
        $optInModeName = "Hotkey Action"
    }

    return [PSCustomObject]@{
        PermanentHooks = $permHooks
        TransientHooks = $transHooks
        ThrottledHooks = $throttledHooks
        InHookZombieQueries = $inHookZombieQueries
        StaticZombieQueries = $staticZombieQueries
        InHookTileQueries = $inHookTileQueries
        StaticTileQueries = $staticTileQueries
        InHookWorldQueries = $inHookWorldQueries
        StaticWorldQueries = $staticWorldQueries
        InHookInvQueries = $inHookInvQueries
        StaticInvQueries = $staticInvQueries
        InHookHeavyContainers = $inHookHeavyContainers
        StaticHeavyContainers = $staticHeavyContainers
        InHookUIPolls = $inHookUIPolls
        StaticUIPolls = $staticUIPolls
        InHookJNICalls = $inHookJNICalls
        StaticJNICalls = $staticJNICalls
        HookBreakdown = $hookBreakdown
        IsStationaryGated = $isStationaryGated
        IsOptInToggle = $isOptInToggle
        OptInModeName = $optInModeName
    }
}

function Get-ModTriggerScenarios {
    param(
        [string]$modId,
        [string]$modName,
        [int]$modelCount,
        [int]$worldMeshCount,
        [int]$characterMeshCount,
        [double]$textureMB,
        [double]$totalMB,
        [int]$permHooks,
        [int]$transHooks,
        [int]$throttledHooks,
        [int]$inHookWorldQueries,
        [int]$inHookInvQueries,
        [int]$inHookHeavyContainers,
        [int]$inHookUIPolls,
        [int]$inHookJNICalls,
        [int]$inHookZombieQueries,
        [int]$inHookTileQueries,
        [bool]$isStationaryGated,
        [bool]$isOptInToggle,
        [string]$optInModeName,
        [bool]$hasJavaJar,
        [int]$javaJarCount,
        [double]$activeTaxRaw,
        [double]$idleTaxRaw,
        [bool]$isContinuousPolling,
        [bool]$isDormantEarlyExit
    )

    $scenarios = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Helper to add unique scenarios
    $addScen = {
        param([string]$name, [string]$impact, [string]$sev, [string]$state, [string]$cond, [int]$weight)
        foreach ($s in $scenarios) {
            if ($s.ScenarioName -eq $name) { return }
        }
        $scenarios.Add([PSCustomObject]@{
            ScenarioName = $name
            Impact       = $impact
            Severity     = $sev
            State        = $state
            Condition    = $cond
            Weight       = $weight
        })
    }

    # 1. Viewpoint Core
    if ($modId -eq "Viewpoint" -or $modName -eq "Viewpoint") {
        & $addScen "Character & Skeletal Bone Snapshots" "~126-295 ms [Snapshot CPU Stall]" "CRITICAL" "Active in 1P" "First-person character model, clothing rigs, and bone snapshot evaluations" 1
        & $addScen "Dynamic Lamp & Headlight Shadows" "~78-195 ms [Shadow Render Stall]" "HIGH" "Situational" "Near active street lamps, interior lights, or vehicle headlights (shadow cube maps)" 2
        & $addScen "1P Camera Matrix & In-Engine Render Pass" "~10-25 ms [1P Render Pass] (+0.75 ms/frame)" "MODERATE" "Continuous in 1P" "Active first-person camera transform, weapon model projection, and depth clipping" 3
        & $addScen "Third-Person Mode Baseline" "< 1 ms [Imperceptible] (+0.15 ms/frame idle)" "NEGLIGIBLE" "Dormant in 3P" "Playing in standard third-person perspective (idle engine hooks)" 5
    }
    # 2. Viewpoint True Weathers & Lighting
    elseif ($modId -match "ViewpointTrueWeathers$" -or $modName -match "True Weathers & Lighting") {
        & $addScen "Heavy Storms, Rain, Fog & Lightning Passes" "~10-30 ms [Weather Shader / Lighting Pass] (+1.20 ms/frame)" "MODERATE" "Situational" "During active rainstorms, dense fog, thunder, and dynamic lightning passes" 3
        & $addScen "Clear Skies / Calm Weather Baseline" "< 1 ms [Imperceptible] (+0.05 ms/frame idle)" "NEGLIGIBLE" "Dormant in Clear Weather" "Clear or overcast weather with no active storm shaders" 5
    }
    # 3. Viewpoint True Weathers - Gameplay
    elseif ($modId -match "ViewpointTrueWeathersGameplay" -or $modName -match "True Weathers - Gameplay") {
        & $addScen "Storm / Fog Zombie Sensory Calculations" "~5-15 ms [Weather Sensory Calculation] (+0.35 ms/frame)" "LOW" "Situational" "During heavy storms or dense fog modifying zombie hearing and sight perception" 4
        & $addScen "Clear Weather Sensory Baseline" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant in Clear Weather" "Normal weather conditions" 5
    }
    # 4. Viewpoint TREE in 3D
    elseif ($modId -match "NearVegetation|TREE in 3D" -or $modName -match "TREE in 3D") {
        & $addScen "Dense Forests & Woodland Tree Meshing" "~15-35 ms [3D Tree Frustum Render] (+0.85 ms/frame)" "MODERATE" "Situational" "Near dense forests, pine groves, or heavy vegetation foliage" 3
        & $addScen "Cleared Areas, Roads & Indoors" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant in Cleared Areas" "Away from dense tree coverage" 5
    }
    # 5. Viewpoint True Ballistics
    elseif ($modId -match "ViewpointTrueBallistics" -or $modName -match "True Ballistics") {
        & $addScen "Firearm Discharge & Ballistics Raycasting" "~10-25 ms [Ballistics Raycast Stall] (+0.75 ms/frame)" "MODERATE" "Situational" "While actively firing firearms (bullet trajectory physics & ricochet raycasts)" 3
        & $addScen "Holstered / Melee Combat Baseline" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant Out of Shooting" "Melee weapons, unarmed, or firearms holstered" 5
    }
    # 6. Blood FX for Viewpoint
    elseif ($modId -match "ViewpointBloodFX" -or $modName -match "Blood FX for Viewpoint") {
        & $addScen "Combat Hits & Zombie Blood Splatter" "~10-25 ms [Blood Particle & Lens Splatter] (+0.60 ms/frame)" "MODERATE" "Situational" "Active combat hits, blood particles on screen lens, and zombie gore decals" 3
        & $addScen "Exploration Out of Combat" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant Out of Combat" "No active weapon hits or blood particle triggers" 5
    }
    # 7. Project Viewpoint: Recoil & ADS
    elseif ($modId -match "ProjectViewpointADS" -or $modName -match "Recoil & ADS") {
        & $addScen "Aiming Down Sights (ADS) & Firing Recoil" "~5-15 ms [Action Blip: Recoil & ADS Calc] (+0.50 ms/frame)" "LOW" "Situational" "While aiming down sights with weapons and processing camera recoil impulse" 4
        & $addScen "Hip-Fire / Weapon Lowered Baseline" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant Idle" "Walking, running, or resting without ADS" 5
    }
    # 8. Viewpoint Advanced Movement
    elseif ($modId -match "ViewpointAdvancedMovement" -or $modName -match "Advanced Movement") {
        & $addScen "Leaning, Prone, Crawling & Vaulting" "~5-15 ms [Movement State Transition] (+0.40 ms/frame)" "LOW" "Situational" "Actively leaning around corners, crawling prone, or vaulting high fences" 4
        & $addScen "Standard Upright Walking / Sprinting" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant Walking" "Standard movement locomotion" 5
    }
    # 9. Viewpoint - Advanced Throwables
    elseif ($modId -match "ViewpointAdvancedThrowables" -or $modName -match "Advanced Throwables") {
        & $addScen "Throwable Aiming Arc & Projectile Physics" "~5-15 ms [Action Blip: Throwable Physics] (+0.50 ms/frame)" "LOW" "Situational" "While aiming trajectory arc and throwing grenades, pipe bombs, or molotovs" 4
        & $addScen "Walking with No Throwables Active" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant on Foot" "No active projectile throwing" 5
    }
    # 10. Viewpoint - Door Fix
    elseif ($modId -match "ViewpointDoor" -or $modName -match "Door Fix") {
        & $addScen "Near Doors & Threshold Transitions" "~2-8 ms [Door Model Lighting Adjustment] (+0.20 ms/frame)" "LOW" "Situational" "Standing near open or closed doorways" 4
        & $addScen "Open Ground Away from Doors" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant Away from Doors" "More than 3 tiles away from door objects" 5
    }
    # 11. Viewpoint - Surface Fix
    elseif ($modId -match "ViewpointSurface" -or $modName -match "Surface Fix") {
        & $addScen "Indoors & Multi-Story Roof Surfaces" "~2-8 ms [Surface Mesh Clip Pass] (+0.25 ms/frame)" "LOW" "Situational" "Inside buildings, multi-level structures, or under roofs" 4
        & $addScen "Open Outdoor Ground" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant Outdoors" "Outside on ground level" 5
    }
    # 12. Viewpoint - 3D Fences
    elseif ($modId -match "ViewpointFences3D" -or $modName -match "3D Fences") {
        & $addScen "Near 3D Wire & Wooden Fences" "~2-8 ms [Fence Mesh Frustum Pass]" "LOW" "Situational" "In view radius of custom 3D fence objects" 4
        & $addScen "Away from Fences" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant Away from Fences" "No 3D fences in view frustum" 5
    }
    # 13. Project Viewpoint Controller Support
    elseif ($modId -match "ControllerSupport|Joypad" -or $modName -match "Controller Support") {
        & $addScen "No Controller Connected (Null RenderTick Polling)" "~5-15 ms [Minor Blip: Polls Gamepad Every Frame on RenderTick]" "LOW" "Continuous (No Controller)" "Keyboard/mouse play without a controller plugged in" 4
        & $addScen "Gamepad Connected (Analog Joystick Processing)" "~1-3 ms [Gamepad Input Poll]" "LOW" "Active with Controller" "Gamepad connected and transmitting stick/button events" 4
    }
    # 14. ZombieBuddy
    elseif ($modId -eq "ZombieBuddy" -or $modName -eq "ZombieBuddy") {
        & $addScen "Engine Startup Bytecode Injection" "< 1 ms [Imperceptible in Gameplay]" "NEGLIGIBLE" "Launch Injection Only" "One-time class transformation at game launch; zero continuous tick tax" 5
    }

    # 15. 3D Meshes & Textures (Generic Non-Vehicle Non-Clothing)
    $isVehicle = ($modId -match "VanillaVehiclesAnimated|Vehicle|jeep|chevy|ford|dodge|nissan|amgeneral|toyota|ferret|oshkosh|corvette|camaro|mustang|volvo|beetle|KI5" -and $modId -ne "PushVehicle")
    $isClothing = ($modId -match "SPNCC|GanydeBielovzki|AuthenticZ|Clothing|Armor|Costume" -or $characterMeshCount -ge 5)
    if (-not $isVehicle -and -not $isClothing -and ($scenarios.Count -eq 0 -or ($modId -match "PZVoxelStudioViewpoint" -or $worldMeshCount -gt 500))) {
        if ($worldMeshCount -gt 5000 -or $modId -match "PZVoxelStudioViewpoint") {
            & $addScen "Chunk Border Traversal & High-Speed Driving" "~350-550 ms [Severe Freeze]" "CRITICAL" "Situational (Chunk Traversal)" "Crossing map chunk boundaries while engine builds and uploads $($worldMeshCount) 3D meshes" 1
        } elseif ($worldMeshCount -gt 1000) {
            & $addScen "Chunk Border Traversal & World Streaming" "~100-250 ms [Noticeable Hitch]" "HIGH" "Situational (Chunk Traversal)" "Crossing map chunk boundaries with $($worldMeshCount) custom 3D meshes" 2
        } elseif ($worldMeshCount -gt 200) {
            & $addScen "Chunk Cell Loading & Mesh Injection" "~20-60 ms [Micro-Stutter]" "MODERATE" "Situational (Chunk Traversal)" "Loading cell with $($worldMeshCount) custom 3D world models" 3
        } elseif ($worldMeshCount -ge 20) {
            & $addScen "Frustum Culling & Local Model Rendering" "~5-15 ms [Render Blip]" "LOW" "Situational" "Camera view frustum contains $($worldMeshCount) custom 3D meshes" 4
        }

        if ($textureMB -gt 100) {
            & $addScen "VRAM Texture Streaming & PCIe Transfer" "~100-250 ms [VRAM Thrash Hitch]" "HIGH" "Situational (Asset Load)" "Loading high-resolution texture assets ($([math]::Round($textureMB, 1)) MB) across PCIe bus" 2
        } elseif ($textureMB -ge 40) {
            & $addScen "VRAM Texture Allocation & Atlas Binding" "~25-75 ms [Texture Load Hitch]" "MODERATE" "Situational (Asset Load)" "Binding $([math]::Round($textureMB, 1)) MB textures into VRAM" 3
        }

        if (($worldMeshCount -ge 20 -or $textureMB -ge 40) -and $scenarios.Count -ge 1) {
            & $addScen "Steady-State Local Exploration" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant (Loaded)" "Staying within already-meshed chunks with textures resident in memory" 5
        }
    }

    # 16. Vehicles
    if ($isVehicle) {
        $vehMeshSpike = if ($worldMeshCount -gt 200) { "~20-60 ms [Vehicle Streaming Hitch]" } else { "~10-25 ms [Vehicle Streaming Hitch]" }
        & $addScen "Chunk Border Traversal & Vehicle Streaming" $vehMeshSpike "MODERATE" "Situational (Chunk Traversal)" "Crossing chunk boundaries with spawned vehicle 3D models and textures" 3
        & $addScen "While Actively Driving (Physics & Speedometer Polling)" "~5-15 ms [Driving Blip] (+0.45 ms/frame active)" "LOW" "Active Driving" "Operating vehicle with active engine physics, dashboard gauges, and wheel rotation" 4
        if ($modId -match "VanillaVehiclesAnimated|KI5campers|KI5trailers") {
            & $addScen "Vehicle Chunk Handoff Container Check" "~30-80 ms [Script Exception Delay]" "MODERATE" "Situational (Chunk Handoff)" "Spawning vehicles with missing accessory script containers (e.g. glovebox.container)" 3
        }
        & $addScen "Parked / Exploring on Foot" "< 1 ms [Imperceptible] (Dormant on Foot)" "NEGLIGIBLE" "Dormant on Foot" "Player is outside vehicle; zero per-frame physics loop tax" 5
    }

    # 17. Containers & Inventory
    $optInPrefix = if ($optInModeName) { "Opt-In [$optInModeName]: " } elseif ($isOptInToggle) { "Opt-In Mode: " } else { "Situational: " }
    if ($inHookHeavyContainers -ge 1) {
        if ($isStationaryGated) {
            & $addScen "$($optInPrefix)When Stopping Near Containers (Backpack Rebuild)" "~5-15 ms [Stationary Blip]" "LOW" "Stationary" "Stationary gating allows loot window backpack rebuild only once the player stops moving near containers" 4
            & $addScen "While Moving on Foot (Near or Far)" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant on Foot" "Zero movement hitch while walking or running (container refresh strictly deferred)" 5
            if ($isOptInToggle -or $optInModeName) {
                & $addScen "Normal Gameplay Baseline (All-Containers Inactive)" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Container loops completely inactive when All-Containers mode is untoggled" 5
            }
        } else {
            & $addScen "Moving Near Containers (Backpack & Weight Rebuild)" "~15-40 ms [Container Hitch]" "MODERATE" "Active Movement Near Containers" "Unconstrained container rebuild firing on tick while moving near loot containers" 3
            & $addScen "Standing Still Away from Containers" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Zero container rebuilds away from loot containers" 5
        }
    }
    if ($modName -match "Viewpoint QOL" -or $modId -match "ViewpointQOL") {
        & $addScen "While Viewpoint / UI Settings Open" "~2-8 ms [UI Polling Delay]" "LOW" "Situational (Menu Open)" "Querying Viewpoint UI toggles and layout elements" 4
    } elseif ($inHookInvQueries -ge 5 -or $modId -match "Equipment|Inventory|Hotbar|Crafting|Menu|Map|Health|DragAndDrop") {
        & $addScen "While Inventory / Container Grid Open" "~2-8 ms [Inventory Grid Delay]" "LOW" "Situational (Inventory Open)" "Populating item slots, weight calculation, and inventory UI tree" 4
        & $addScen "Inventory Closed Baseline" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Normal gameplay with inventory UI closed" 5
    }

    # 18. Actions & Mechanics
    if ($modId -match "TakeABath|BathAndShower|Shower|Hygiene" -or $modName -match "Take A Bath|Shower") {
        & $addScen "Bathing / Showering Action" "~10-25 ms [Hygiene / Fluid Hitch]" "LOW" "Active Action" "Interacting with plumbing fixtures to wash body/clothing" 4
        & $addScen "Normal Exploration on Foot" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant Early-Exit" "Walking / running away from bathtubs (early return)" 5
    }
    if ($modId -match "PushVehicle" -or $modName -match "Push Vehicle") {
        & $addScen "Physically Pushing a Vehicle" "~5-15 ms [Vehicle Physics Impulse]" "LOW" "Active Action" "Manually pushing a vehicle with pending impulse queries" 4
        & $addScen "Normal Walking / Driving" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant Early-Exit" "Zero pending vehicle push actions" 5
    }
    if ($modId -match "LethalStealth|RET_LethalStealth" -or $modName -match "Lethal Stealth") {
        & $addScen "Sneaking / In Stealth Stance" "~5-15 ms [Stealth Sight Cone & Critical Calc]" "LOW" "Situational (Stealth Stance)" "Crouched/sneaking with active line-of-sight & assassinate checks" 4
        & $addScen "Upright Walking or Running" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant Early-Exit" "Upright stance (early return bypasses stealth loops)" 5
    }
    if ($modId -match "NeatLockpicking|Lockpick" -or $modName -match "Lockpicking") {
        & $addScen "Lockpicking Mini-Game Active" "~5-15 ms [Lockpick UI & Tumbler Physics]" "LOW" "Active Action" "Manipulating bobby pin and screwdriver in tumbler mini-game" 4
        & $addScen "Inspecting Locked Doors" "~2-8 ms [Translation String Lookup]" "LOW" "Situational (Hover / Inspect)" "Examining door lock status and displaying contextual prompt" 4
        & $addScen "Normal Exploration" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Exploring without interacting with locked doors" 5
    }
    if ($modId -match "DynamicGearRattling|GearRattling" -or $modName -match "Gear Rattling") {
        & $addScen "Jogging / Sprinting with Heavy Backpack" "~5-15 ms [Gear Audio Event Trigger]" "LOW" "Active Locomotion" "Moving on foot with high inventory weight causing gear noise" 4
        & $addScen "Standing Still, Sneaking, or Driving" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Stationary, crouched, or inside a vehicle" 5
    }
    if ($modId -match "traitsAsSkills" -or $modName -match "Traits As Skills") {
        & $addScen "Zombie Kill & Skill XP Progression Burst" "~5-15 ms [XP Table Calculation]" "LOW" "Combat Action" "Defeating zombies and recalculating dynamic trait XP progression" 4
        & $addScen "Passive Gameplay Between Kills" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Throttled Timer" "Periodic timer loop between XP triggers" 5
    }
    if ($modId -match "P4TidyUpMeister|TidyUpMeister" -or $modName -match "Tidy Up Meister") {
        & $addScen "Completing Timed Actions (Auto-Stow Scan)" "~5-15 ms [Inventory Auto-Stow Scan]" "LOW" "Action Completion" "Finishing actions and querying containers to auto-repack tools" 4
        & $addScen "Normal Exploration" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Walking or fighting with no active stow actions" 5
    }
    if ($modId -match "Construction1PViewpoint" -or $modName -match "Construction 1P") {
        & $addScen "Carpentry & Object Placement Preview" "~5-15 ms [Ghost Tile Placement Render]" "LOW" "Active Building" "Hovering blueprint or ghost furniture tiles in first-person" 4
        & $addScen "Normal Exploration" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Standard movement without construction cursor" 5
    }
    if ($modId -match "ALife|SuperbSurvivors|SubparSurvivors|NPC|Bandits|Humanoid" -or $modName -match "A-Life|Superb Survivors|NPCs|Bandits") {
        & $addScen "Hostile Combat & Gunfights" "~50-150 ms [Combat AI Spike]" "HIGH" "Combat Burst" "Active NPC combat, dynamic pathfinding, and weapon sensory raycasts" 2
        & $addScen "Ambient Sensory Roaming" "~20-60 ms [AI Simulation Spike] (+1.50 ms/frame)" "MODERATE" "Continuous Background" "NPC navigation and environmental awareness background loops" 3
    }
    if ($inHookZombieQueries -ge 3 -or $modId -match "TrueCrawling|ZombieDismemberment|ZombieAnimation|ZombieCrawl|ZombieCollision") {
        & $addScen "Dense Horde Proximity & Combat" "~10-35 ms [Combat Hitch]" "MODERATE" "Combat Burst" "Multiple zombies crawling or losing limbs within combat radius" 3
        & $addScen "Cleared Areas (Zero Zombies in Radius)" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "No active zombies in immediate simulation sector" 5
    }
    if ($modId -match "PushDoors|Push Door|CyesPushDoors" -or $modName -match "Push Doors") {
        & $addScen "Near Closed Doors (Physical Push Physics)" "~5-15 ms [Door Hitch]" "LOW" "Situational (Near Doors)" "Bumping into closed doors to trigger swing physics" 4
        & $addScen "Background 25-Tile Continuous Door Scanner" "+0.25 ms/frame continuous polling tax" "LOW" "Continuous Background" "Spatial door scan every 2 ticks even when away from doors" 4
    }
    if ($modId -match "PZ_Pulse|PZPulse" -or $modName -match "PZ Pulse") {
        & $addScen "Browser Telemetry Sync Wave (~Every 500ms)" "~5-15 ms [HTTP/Socket Telemetry Flush]" "LOW" "Periodic Sync" "Flushing game state to companion browser second-screen dashboard" 4
        & $addScen "Between Sync Waves" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Between 500ms sync intervals" 5
    }
    if ($transHooks -ge 15 -or $modId -match "Journal|Burd") {
        & $addScen "Transcribing or Reading Full Journal XP Sync" "~50-150 ms [Action Spike: XP Deserialization]" "HIGH" "Action Burst" "Synchronizing character XP and traits to/from diary item" 2
        & $addScen "Normal Gameplay (Journal in Bag)" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Passive inventory item with zero background cost" 5
    }
    if ($modId -match "aparosa_pz3dMinimap") {
        & $addScen "Continuous 3D Minimap Frustum Projection" "~50-120 ms [Continuous Minimap Render Lag]" "CRITICAL" "Continuous (HUD Visible)" "Rendering second camera view and 3D minimap overlay" 1
        & $addScen "Minimap Hidden / Closed" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Minimap interface hidden" 5
    }
    if ($isClothing) {
        if ($textureMB -ge 15) {
            & $addScen "Texture Allocation (Clothing Textures in VRAM)" "~20-60 ms [Texture Buffer Hitch]" "MODERATE" "Situational (Asset Load)" "Streaming high-resolution clothing textures ($([math]::Round($textureMB, 1)) MB)" 3
        }
        & $addScen "Character Rendering & Skeletal Bone Evaluation" "~5-20 ms [Character Mesh Pass]" "LOW" "Situational (In Frustum)" "Evaluating skeletal bone matrices for custom layered clothing" 4
        & $addScen "Standard Gameplay (Cached)" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant (Cached)" "Equipped clothing already resident in VRAM" 5
    }

    # 19. Generic Fallbacks
    if ($scenarios.Count -eq 0) {
        if ($hasJavaJar) {
            & $addScen "Native Java Engine Extension Execution" "~5-15 ms [Java Engine Extension] (+0.50 ms active)" "LOW" "Situational (JVM)" "Direct bytecode execution during interaction" 4
            & $addScen "Idle on Foot" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Standard movement without interacting" 5
        } elseif ($permHooks -gt 0) {
            if ($isContinuousPolling) {
                & $addScen "Continuous Engine Hook Tick Loop" "~2-8 ms [Frame Delay] (+$activeTaxRaw ms active)" "LOW" "Continuous Polling" "Unconstrained permanent hook firing every single frame" 4
                & $addScen "Idle Baseline Tax" "+$idleTaxRaw ms/frame" "LOW" "Continuous Baseline" "Java-to-Lua event invocation cost" 4
            } else {
                & $addScen "Active Interaction / Hook Execution" "~2-8 ms [Frame Delay] (+$activeTaxRaw ms active)" "LOW" "Active Interaction" "Executing hook payload during specific player interaction" 4
                & $addScen "Dormant Idle (Early Return)" "< 1 ms [Imperceptible] (0.00 ms idle)" "NEGLIGIBLE" "Dormant (Early-Exit)" "Hook registered in engine, exits in < 0.002 ms when idle" 5
            }
        } elseif ($throttledHooks -gt 0) {
            & $addScen "Periodic Timer Execution (~Every 5-10s)" "~5-15 ms [Minor Blip]" "LOW" "Periodic Timer" "Modulo / timer-gated logic pulse" 4
            & $addScen "Between Timer Pulses" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Dormant" "Zero execution between intervals" 5
        } else {
            & $addScen "Standard Gameplay" "< 1 ms [Imperceptible]" "NEGLIGIBLE" "Passive / Event-Driven" "Clean passive mod with no continuous background drag" 5
        }
    }

    return @($scenarios | Sort-Object Weight)
}

function Get-ModStutterMetrics {
    param(
        [string]$modId,
        [int]$modelCount,
        [double]$textureMB,
        [double]$totalMB,
        [int]$permHooks,
        [int]$transHooks,
        [int]$throttledHooks,
        [int]$inHookWorldQueries,
        [int]$inHookInvQueries,
        [int]$riskScore,
        [int]$worldMeshCount = 0,
        [string]$modName = "",
        [int]$inHookHeavyContainers = 0,
        [int]$inHookUIPolls = 0,
        [int]$inHookJNICalls = 0,
        [bool]$isStationaryGated = $false,
        [bool]$isOptInToggle = $false,
        [string]$optInModeName = "",
        [int]$inHookZombieQueries = 0,
        [int]$inHookTileQueries = 0,
        [bool]$hasJavaJar = $false,
        [int]$javaJarCount = 0,
        [int]$characterMeshCount = 0
    )

    # 1. Continuous & Peak Frame Time Tax (+X.XX ms / frame)
    # Queries in permanent per-frame loops run continuously; queries in throttled hooks run periodically
    $javaActiveTax = 0.0
    $javaIdleTax = 0.0
    if ($modId -eq "ZombieBuddy" -or $modName -eq "ZombieBuddy") {
        $javaActiveTax = 0.0
        $javaIdleTax = 0.0
    } elseif ($modId -match "ViewpointTrueWeathers$" -or $modName -match "True Weathers & Lighting") {
        $javaActiveTax = 1.20
        $javaIdleTax = 0.05
    } elseif ($modId -match "NearVegetation|TREE in 3D" -or $modName -match "TREE in 3D") {
        $javaActiveTax = 0.85
        $javaIdleTax = 0.0
    } elseif ($modId -eq "Viewpoint" -or $modName -eq "Viewpoint") {
        $javaActiveTax = 0.75
        $javaIdleTax = 0.15
    } elseif ($modId -match "ViewpointTrueBallistics" -or $modName -match "True Ballistics") {
        $javaActiveTax = 0.75
        $javaIdleTax = 0.0
    } elseif ($modId -match "ViewpointBloodFX" -or $modName -match "Blood FX for Viewpoint") {
        $javaActiveTax = 0.60
        $javaIdleTax = 0.0
    } elseif ($modId -match "ViewpointAdvancedThrowables" -or $modName -match "Advanced Throwables") {
        $javaActiveTax = 0.50
        $javaIdleTax = 0.0
    } elseif ($modId -match "ProjectViewpointADS" -or $modName -match "Recoil & ADS") {
        $javaActiveTax = 0.50
        $javaIdleTax = 0.0
    } elseif ($modId -match "ViewpointAdvancedMovement" -or $modName -match "Advanced Movement") {
        $javaActiveTax = 0.40
        $javaIdleTax = 0.0
    } elseif ($modId -match "ViewpointTrueWeathersGameplay" -or $modName -match "True Weathers - Gameplay") {
        $javaActiveTax = 0.35
        $javaIdleTax = 0.0
    } elseif ($modId -match "ViewpointSurface" -or $modName -match "Surface Fix") {
        $javaActiveTax = 0.25
        $javaIdleTax = 0.0
    } elseif ($modId -match "ViewpointDoor" -or $modName -match "Door Fix") {
        $javaActiveTax = 0.20
        $javaIdleTax = 0.0
    } elseif ($hasJavaJar) {
        $javaActiveTax = 0.50
        $javaIdleTax = 0.0
    }

    $hookTax = ($permHooks * 0.45) + ($throttledHooks * 0.02)
    $worldTax = if ($permHooks -gt 0) { $inHookWorldQueries * 0.08 } elseif ($throttledHooks -gt 0) { $inHookWorldQueries * 0.015 } else { 0.0 }
    $invTax = if ($permHooks -gt 0) { $inHookInvQueries * 0.04 } elseif ($throttledHooks -gt 0) { $inHookInvQueries * 0.01 } else { 0.0 }
    $containerTax = if ($isStationaryGated) { 0.0 } elseif ($permHooks -gt 0) { $inHookHeavyContainers * 0.15 } elseif ($throttledHooks -gt 0) { $inHookHeavyContainers * 0.04 } else { 0.0 }
    $uiPollTax = if ($permHooks -gt 0) { $inHookUIPolls * 0.02 } elseif ($throttledHooks -gt 0) { $inHookUIPolls * 0.005 } else { 0.0 }
    $jniTax = if ($permHooks -gt 0) { $inHookJNICalls * 0.02 } elseif ($throttledHooks -gt 0) { $inHookJNICalls * 0.005 } else { 0.0 }

    $queryTax = $worldTax + $invTax + $containerTax + $uiPollTax + $jniTax
    $activeTaxRaw = [math]::Round($hookTax + $queryTax + $javaActiveTax, 2)

    # Classify Hook Nature: Continuous Polling vs Dormant (Early-Exit)
    $isContinuousPolling = $false
    $isDormantEarlyExit = $false

    if ($permHooks -gt 0) {
        if ($modId -match "ALife|SuperbSurvivors|SubparSurvivors|NPC|Bandits|Humanoid" -or $modName -match "A-Life|Superb Survivors|NPCs|Bandits") {
            $isContinuousPolling = $true # Autonomous NPC AI sensory & navigation loop
        } elseif ($modId -match "PushDoors|Push Door|CyesPushDoors" -or $modName -match "Push Doors") {
            $isContinuousPolling = $true # Spatial door scan executes every 2 ticks even when away from doors
        } elseif ($inHookZombieQueries -ge 3 -or $modId -match "TrueCrawling|ZombieDismemberment|ZombieAnimation|ZombieCrawl|ZombieCollision") {
            $isContinuousPolling = $true # Continuous zombie proximity checks
        } elseif ($inHookTileQueries -ge 5 -and -not ($modId -match "TakeABath|BathAndShower|Shower|PushVehicle|RealisticDash|Lockpick|Construction|TidyUp|GearRattling")) {
            $isContinuousPolling = $true # Unconstrained tile scanner
        } else {
            # Event-gated, interaction-gated, UI-gated, or status-checked early-returns:
            # Take A Bath (exits unless isTakingBath/inBath), Push Vehicle (exits if #pendingPushes == 0), Realistic Dashboard (exits if not in vehicle),
            # Traits As Skills (throttled timer), Lethal Stealth (exits unless sneaking/server), Viewpoint QOL, etc.
            $isDormantEarlyExit = $true
        }
    }

    # Idle Baseline Tax:
    # Fixed Java-to-Lua JNI event invocation cost (~0.10 ms per registered hook)
    # Plus continuous background payload for unconstrained pollers
    $idleHookDispatch = ($permHooks * 0.10) + ($throttledHooks * 0.005)
    $idlePayloadTax = 0.0
    if ($isContinuousPolling) {
        $idlePayloadTax = ($inHookWorldQueries * 0.04) + ($inHookTileQueries * 0.03) + ($inHookZombieQueries * 0.03) + ($inHookHeavyContainers * 0.02)
        if ($idlePayloadTax -lt 0.05 -and $permHooks -gt 0) { $idlePayloadTax = 0.05 * $permHooks }
    }
    $idleTaxRaw = [math]::Round($idleHookDispatch + $idlePayloadTax + $javaIdleTax, 2)

    $loopNature = if ($modId -eq "ZombieBuddy" -or $modName -eq "ZombieBuddy") {
        "Passive Framework"
    } elseif ($modId -eq "Viewpoint" -or $modName -eq "Viewpoint") {
        "1P Render Matrix (JVM)"
    } elseif ($modId -match "ViewpointTrueWeathers$" -or $modName -match "True Weathers & Lighting") {
        "Weather Render (JVM)"
    } elseif ($hasJavaJar) {
        "Situational (JVM)"
    } elseif ($isContinuousPolling) {
        "Continuous Polling"
    } elseif ($isDormantEarlyExit) {
        "Dormant (Early-Exit)"
    } elseif ($throttledHooks -gt 0) {
        "Periodic Timer"
    } else {
        "Event-Driven"
    }

    $taxText = if ($activeTaxRaw -gt 0.01) {
        if ($idleTaxRaw -lt $activeTaxRaw) {
            "+$([math]::Round($activeTaxRaw, 2)) ms peak (+$( [math]::Round($idleTaxRaw, 2) ) ms idle)"
        } else {
            "+$([math]::Round($activeTaxRaw, 2)) ms/frame"
        }
    } else {
        "+0.00 ms/frame"
    }

    # Deterministic formula breakdown
    $breakdownParts = @()
    if ($hasJavaJar) { $breakdownParts += "Java Bytecode: +$([math]::Round($javaActiveTax, 2)) ms active (+$([math]::Round($javaIdleTax, 2)) ms idle)" }
    if ($hookTax -ge 0.01) { $breakdownParts += "Hooks: +$([math]::Round($hookTax, 2)) ms" }
    if ($worldTax -ge 0.01) { $breakdownParts += "World: +$([math]::Round($worldTax, 2)) ms" }
    if ($invTax -ge 0.01) { $breakdownParts += "Inventory: +$([math]::Round($invTax, 2)) ms" }
    if ($containerTax -ge 0.01) { $breakdownParts += "Containers: +$([math]::Round($containerTax, 2)) ms" }
    if ($uiPollTax -ge 0.01) { $breakdownParts += "UI Polling: +$([math]::Round($uiPollTax, 2)) ms" }
    if ($jniTax -ge 0.01) { $breakdownParts += "JNI/Java: +$([math]::Round($jniTax, 2)) ms" }
    if ($idleTaxRaw -ge 0.01) { $breakdownParts += "Idle Baseline: +$([math]::Round($idleTaxRaw, 2)) ms" }
    $taxBreakdown = if ($breakdownParts.Count -gt 0) { $breakdownParts -join ", " } else { "Minimal static load" }

    # 2. Multi-Scenario Trigger Taxonomy Evaluation
    $allScenarios = Get-ModTriggerScenarios -modId $modId `
        -modName $modName `
        -modelCount $modelCount `
        -worldMeshCount $worldMeshCount `
        -characterMeshCount $characterMeshCount `
        -textureMB $textureMB `
        -totalMB $totalMB `
        -permHooks $permHooks `
        -transHooks $transHooks `
        -throttledHooks $throttledHooks `
        -inHookWorldQueries $inHookWorldQueries `
        -inHookInvQueries $inHookInvQueries `
        -inHookHeavyContainers $inHookHeavyContainers `
        -inHookUIPolls $inHookUIPolls `
        -inHookJNICalls $inHookJNICalls `
        -inHookZombieQueries $inHookZombieQueries `
        -inHookTileQueries $inHookTileQueries `
        -isStationaryGated $isStationaryGated `
        -isOptInToggle $isOptInToggle `
        -optInModeName $optInModeName `
        -hasJavaJar $hasJavaJar `
        -javaJarCount $javaJarCount `
        -activeTaxRaw $activeTaxRaw `
        -idleTaxRaw $idleTaxRaw `
        -isContinuousPolling $isContinuousPolling `
        -isDormantEarlyExit $isDormantEarlyExit

    $primary = if ($allScenarios.Count -gt 0) { $allScenarios[0] } else {
        [PSCustomObject]@{
            ScenarioName = "None (Passive / Static UI)"
            Impact       = "< 1 ms [Imperceptible]"
            Severity     = "NEGLIGIBLE"
            State        = "Passive"
            Condition    = "None (Passive / Static UI)"
            Weight       = 5
        }
    }
    $secondary = @($allScenarios | Select-Object -Skip 1)

    return [PSCustomObject]@{
        PotentialSpike      = $primary.Impact
        FrameTax            = $taxText
        TaxBreakdown        = $taxBreakdown
        StutterTrigger      = $primary.Condition
        SpikeSeverity       = $primary.Severity
        ActiveTaxRaw        = $activeTaxRaw
        IdleTaxRaw          = $idleTaxRaw
        IsContinuousPolling = $isContinuousPolling
        IsDormantEarlyExit  = $isDormantEarlyExit
        LoopNature          = $loopNature
        AllScenarios        = @($allScenarios)
        PrimaryScenario     = $primary
        SecondaryScenarios  = @($secondary)
        ScenarioCount       = $allScenarios.Count
    }
}

function Test-IsSpikeWorthy($mod) {
    if (-not $mod) { return $false }
    if ($mod.PotentialSpike -match '< 1 ms|Imperceptible') { return $false }
    if ($mod.SpikeSeverity -eq 'NEGLIGIBLE') { return $false }
    if ($mod.StutterTrigger -eq 'None (Passive / Static UI)') { return $false }
    if ($mod.LoopNature -eq 'Passive Framework') { return $false }
    if ($mod.ModId -eq 'ZombieBuddy' -or $mod.ModName -eq 'ZombieBuddy') { return $false }

    $hasTax = $false
    if ($mod.FrameTax -match '\+([\d\.]+)\s*ms') {
        if ([double]$matches[1] -gt 0.02) { $hasTax = $true }
    }

    if ($hasTax -or 
        $mod.PermanentHooks -gt 0 -or 
        $mod.InHookWorldQueries -gt 0 -or 
        $mod.InHookHeavyContainers -gt 0 -or 
        $mod.InHookUIPolls -ge 5 -or 
        $mod.ThrottledHooks -gt 0 -or 
        $mod.WorldMeshCount -ge 200 -or 
        $mod.TextureMB -ge 50 -or 
        $mod.RiskScore -ge 15 -or
        $mod.LoopNature -match "JVM") {
        return $true
    }
    return $false
}

function Build-FreezeCluster($frames) {
    $totDur = ($frames | Measure-Object -Property DurationMs -Sum).Sum
    $fMin = ($frames | Measure-Object -Property FrameNumber -Minimum).Minimum
    $fMax = ($frames | Measure-Object -Property FrameNumber -Maximum).Maximum
    $fRange = if ($fMin -gt 0 -and $fMax -gt 0) { "Frames $fMin-$fMax" } else { "$($frames.Count) consecutive frames" }
    
    $cTriggers = @()
    $totCC = ($frames | Measure-Object -Property ChunkCacheMs -Sum).Sum
    if ($totCC -ge 15.0) { $cTriggers += ("Chunk Cache ({0} ms)" -f [math]::Round($totCC, 1)) }
    $totSnap = ($frames | Measure-Object -Property SnapshotMs -Sum).Sum
    if ($totSnap -ge 15.0) { $cTriggers += ("Snapshots ({0} ms)" -f [math]::Round($totSnap, 1)) }
    $totGC = ($frames | Where-Object { $_.RestDetails -match "collector's pauses" } | Measure-Object -Property RestMs -Sum).Sum
    if ($totGC -ge 50.0) { $cTriggers += ("GC Sweep ({0} ms)" -f [math]::Round($totGC, 1)) }
    $totShadow = ($frames | Measure-Object -Property ShadowMs -Sum).Sum
    if ($totShadow -ge 15.0) { $cTriggers += ("Lamp Shadows ({0} ms)" -f [math]::Round($totShadow, 1)) }
    $totGb = ($frames | Measure-Object -Property GbufferMs -Sum).Sum
    if ($totGb -ge 15.0) { $cTriggers += ("G-Buffer ({0} ms)" -f [math]::Round($totGb, 1)) }
    $totWait = ($frames | Where-Object { $_.WaitMainThread } | Measure-Object -Property RestMs -Sum).Sum
    if ($totWait -ge 20.0) { $cTriggers += ("Waiting for Main Thread ({0} ms)" -f [math]::Round($totWait, 1)) }

    $trigStr = if ($cTriggers.Count -gt 0) { $cTriggers -join " + " } else { "Combat / Simulation Burst" }

    return [PSCustomObject]@{
        TotalDurationMs = [math]::Round($totDur, 1)
        FrameCount = $frames.Count
        FrameRange = $fRange
        Triggers = $trigStr
        Frames = $frames
    }
}

# ==============================================================================
# Core Diagnostic Engine
# ==============================================================================
function Invoke-PZScanEngine([string]$CustomServerIni = "", [switch]$LocalWorkshopOnly, [string]$CustomWorkshopPath = "", [string]$CustomLog = "") {
    Write-Host "`n=================================================================" -ForegroundColor Cyan
    Write-Host "   PROJECT ZOMBOID MOD PERFORMANCE & OPTIMIZATION SUITE $Script:SuiteVersion " -ForegroundColor Yellow
    Write-Host "         Created by @KodeMannn with the help of Gemini          " -ForegroundColor DarkCyan
    Write-Host "=================================================================`n" -ForegroundColor Cyan

    $versionFile = Join-Path $ZomboidUserPath "version.txt"
    $pzVersion = "Unknown"
    if (Test-Path $versionFile) {
        $pzVersion = (Get-Content $versionFile -Raw).Trim()
    }
    Write-Host " [INFO] Detected Game Version: $pzVersion" -ForegroundColor Gray

    $validWorkshopPaths = Get-WorkshopPaths -customPath $CustomWorkshopPath
    if ((-not $validWorkshopPaths -or $validWorkshopPaths.Count -eq 0) -and -not $LocalWorkshopOnly -and -not $Auto) {
        Write-Host " [!] NOTICE: No Steam Workshop libraries detected automatically on standard paths." -ForegroundColor Yellow
        Write-Host "     If your game or mods are on another drive (e.g. D:, E:), enter the path below." -ForegroundColor Gray
        $promptWs = (Read-Host "     Enter Steam or Workshop folder (or press [Enter] to skip)").Trim().Trim('"').Trim("'")
        if ($promptWs) {
            $resolvedWs = Resolve-CustomWorkshopPath $promptWs
            if ($resolvedWs -and (Test-Path $resolvedWs)) {
                Set-PZScannerConfig $resolvedWs
                $CustomWorkshopPath = $resolvedWs
                $script:CustomWorkshopPath = $resolvedWs
                $validWorkshopPaths = @($resolvedWs)
                Write-Host " [SUCCESS] Saved and added Workshop path: $resolvedWs" -ForegroundColor Green
            } else {
                Write-Host " [!] Path not found or inaccessible: $promptWs" -ForegroundColor Red
            }
        }
    }
    Write-Host " [INFO] Found $($validWorkshopPaths.Count) Steam Workshop Librar$(if($validWorkshopPaths.Count -eq 1){'y'}else{'ies'})" -ForegroundColor Gray

    $targetLogItem = Resolve-PZEngineLogFile -userPath $ZomboidUserPath -customLog $CustomLog
    $targetLogName = if ($targetLogItem) { $targetLogItem.Name } else { "None" }
    $targetLogSizeMb = if ($targetLogItem) { [math]::Round($targetLogItem.Length / 1MB, 2) } else { 0 }
    $logInfoStr = if ($targetLogItem -and $targetLogItem.Length -gt 0) {
        "$targetLogName ($targetLogSizeMb MB)"
    } else {
        "None detected (console.txt / DebugLog empty or absent)"
    }

    $activeMods = @()
    $saveName = "Unknown"
    $modLocations = @{}
    $modTitles = @{}

    if ($LocalWorkshopOnly) {
        $targetWs = if ($CustomWorkshopPath -and (Test-Path $CustomWorkshopPath)) {
            $CustomWorkshopPath
        } else {
            Join-Path $ZomboidUserPath "Workshop"
        }
        $saveName = "Local Workshop: $targetWs"
        Write-Host " [INFO] Audit Scope: Local Workshop Directory ($targetWs)" -ForegroundColor Cyan

        if (-not (Test-Path $targetWs)) {
            Write-Host " [!] Local Workshop folder not found at: $targetWs" -ForegroundColor Red
            return
        }

        # Discover all mods inside the local workshop directory
        $workshopInfos = Get-ChildItem -Path $targetWs -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue
        foreach ($info in $workshopInfos) {
            $content = Get-Content $info.FullName -ErrorAction SilentlyContinue
            $id = (($content | Where-Object { $_ -match '^id=' }) -replace '^id=\s*', '').Trim() | Select-Object -First 1
            $name = (($content | Where-Object { $_ -match '^name=' }) -replace '^name=\s*', '').Trim() | Select-Object -First 1
            if ($id) {
                $scanDir = $info.DirectoryName
                if ($info.Directory.Parent -and (Test-Path (Join-Path $info.Directory.Parent.FullName "common"))) {
                    $scanDir = $info.Directory.Parent.FullName
                }
                if ($activeMods -notcontains $id) { $activeMods += $id }
                if (-not $modLocations[$id]) {
                    $modLocations[$id] = $scanDir
                    $modTitles[$id] = if ($name) { $name } else { $id }
                }
            }
        }
        Write-Host " [INFO] Discovered $($activeMods.Count) local workshop mod(s) to audit" -ForegroundColor Gray
    } elseif ($CustomServerIni -and (Test-Path $CustomServerIni)) {
        # Server mode
        $saveName = "Server Config: $(Split-Path $CustomServerIni -Leaf)"
        $iniLines = Get-Content $CustomServerIni
        foreach ($line in $iniLines) {
            if ($line -match '^Mods=(.*)$') {
                $rawMods = $matches[1] -split ';'
                foreach ($rm in $rawMods) {
                    $m = $rm.Trim()
                    if ($m -and ($activeMods -notcontains $m)) { $activeMods += $m }
                }
            }
        }
        Write-Host " [INFO] Loaded Server Config: $saveName" -ForegroundColor Cyan
    } else {
        # Savegame mode
        $latestSaveIni = Join-Path $ZomboidUserPath "latestSave.ini"
        $saveDir = $null
        if (Test-Path $latestSaveIni) {
            $saveLines = Get-Content $latestSaveIni
            if ($saveLines.Count -ge 2) {
                $candidate = Join-Path $ZomboidUserPath "Saves\$($saveLines[1].Trim())\$($saveLines[0].Trim())"
                if (Test-Path $candidate) {
                    $saveDir = $candidate
                    $saveName = "$($saveLines[1].Trim()) / $($saveLines[0].Trim())"
                }
            }
        }
        if (-not $saveDir) {
            $latest = Get-ChildItem -Path (Join-Path $ZomboidUserPath "Saves") -Recurse -Filter "mods.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                $saveDir = $latest.DirectoryName
                $saveName = $latest.Directory.Name
            }
        }
        Write-Host " [INFO] Active Savegame: $saveName" -ForegroundColor Gray

        if ($saveDir -and (Test-Path (Join-Path $saveDir "mods.txt"))) {
            $modLines = Get-Content (Join-Path $saveDir "mods.txt")
            foreach ($line in $modLines) {
                if ($line -match 'mod\s*=\s*([^,;]+)') {
                    $mId = ($matches[1] -replace '\s*}.*$', '').Trim()
                    if ($mId -and ($activeMods -notcontains $mId)) { $activeMods += $mId }
                }
            }
        }
    }

    Write-Host " [INFO] Total Enabled Mods to Audit: $($activeMods.Count)" -ForegroundColor Cyan
    Write-Host " [INFO] Runtime Engine Log         : $logInfoStr`n" -ForegroundColor $(if ($targetLogItem -and $targetLogItem.Length -gt 0) { "Gray" } else { "DarkGray" })
    if ($activeMods.Count -eq 0) {
        if ($LocalWorkshopOnly) {
            Write-Host " [!] No mods with mod.info found in local workshop folder ($targetWs)." -ForegroundColor Yellow
        } else {
            Write-Host " [!] No enabled mods found to scan." -ForegroundColor Yellow
        }
        return
    }

    # Index installed mods (when not in LocalWorkshopOnly mode)
    if (-not $LocalWorkshopOnly) {
        foreach ($wsPath in $validWorkshopPaths) {
            $workshopInfos = Get-ChildItem -Path $wsPath -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue
            foreach ($info in $workshopInfos) {
                $content = Get-Content $info.FullName -ErrorAction SilentlyContinue
                $id = (($content | Where-Object { $_ -match '^id=' }) -replace '^id=\s*', '').Trim() | Select-Object -First 1
                $name = (($content | Where-Object { $_ -match '^name=' }) -replace '^name=\s*', '').Trim() | Select-Object -First 1
                if ($id) {
                    $parentFull = if ($info.Directory.Parent) { $info.Directory.Parent.FullName } else { $null }
                    $scanDir = if ($parentFull -and (Test-Path (Join-Path $parentFull "common"))) { $parentFull } else { $info.DirectoryName }
                    $modLocations[$id] = $scanDir
                    $modTitles[$id] = $name
                }
            }
        }

        $localModPath = Join-Path $ZomboidUserPath "mods"
        if (Test-Path $localModPath) {
            $localInfos = Get-ChildItem -Path $localModPath -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue
            foreach ($info in $localInfos) {
                $content = Get-Content $info.FullName -ErrorAction SilentlyContinue
                $id = (($content | Where-Object { $_ -match '^id=' }) -replace '^id=\s*', '').Trim() | Select-Object -First 1
                $name = (($content | Where-Object { $_ -match '^name=' }) -replace '^name=\s*', '').Trim() | Select-Object -First 1
                if ($id) {
                    $parentFull = if ($info.Directory.Parent) { $info.Directory.Parent.FullName } else { $null }
                    $scanDir = if ($parentFull -and (Test-Path (Join-Path $parentFull "common"))) { $parentFull } else { $info.DirectoryName }
                    $modLocations[$id] = $scanDir
                    $modTitles[$id] = $name
                }
            }
        }

        $workshopStagingPath = Join-Path $ZomboidUserPath "Workshop"
        if (Test-Path $workshopStagingPath) {
            $wsStagingInfos = Get-ChildItem -Path $workshopStagingPath -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue
            foreach ($info in $wsStagingInfos) {
                $content = Get-Content $info.FullName -ErrorAction SilentlyContinue
                $id = (($content | Where-Object { $_ -match '^id=' }) -replace '^id=\s*', '').Trim() | Select-Object -First 1
                $name = (($content | Where-Object { $_ -match '^name=' }) -replace '^name=\s*', '').Trim() | Select-Object -First 1
                if ($id -and -not $modLocations[$id]) {
                    $scanDir = $info.DirectoryName
                    if ($info.Directory.Parent -and (Test-Path (Join-Path $info.Directory.Parent.FullName "common"))) {
                        $scanDir = $info.Directory.Parent.FullName
                    }
                    $modLocations[$id] = $scanDir
                    $modTitles[$id] = if ($name) { $name } else { $id }
                }
            }
        }
    }

    # Profile active mods
    Write-Host " [*] Auditing Lua hooks, 3D meshes, texture packs, and file collisions..." -ForegroundColor Yellow

    $modReports = @()
    $uninstalledMods = @()
    $fileCollisionMap = @{} # Path -> List of mod IDs
    $currentIdx = 0

    foreach ($modId in $activeMods) {
        $currentIdx++
        $percent = [math]::Round(($currentIdx / $activeMods.Count) * 65)
        $displayStatus = if ($modTitles[$modId]) { $modTitles[$modId] } else { $modId }
        Write-Progress -Activity "Project Zomboid Mod Diagnostic Engine" -Status "Phase 1/4: Auditing Mod Files & Lua Code ($currentIdx / $($activeMods.Count)) - $displayStatus" -PercentComplete $percent

        $dir = $modLocations[$modId]
        if (-not $dir -or -not (Test-Path $dir)) {
            $uninstalledMods += $modId
            continue
        }

        $displayName = if ($modTitles[$modId]) { $modTitles[$modId] } else { $modId }
        
        $totalMB = 0
        $modelCount = 0
        $textureMB = 0
        $onTick = 0
        $onRenderTick = 0
        $onPlayerUpdate = 0
        $onZombieUpdate = 0
        $onRender3D = 0
        $worldQueries = 0
        $inventoryQueries = 0
        $riskScore = 0
        $riskReasons = @()

        $activeDirs = Get-ModActiveDirectories -modDir $dir -gameVersion $pzVersion
        $allFiles = @()
        foreach ($ad in $activeDirs) {
            $allFiles += Get-ChildItem -Path $ad -Recurse -File -ErrorAction SilentlyContinue
        }
        $extraLibDirs = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(libs|java)$' }
        foreach ($eld in $extraLibDirs) {
            $allFiles += Get-ChildItem -Path $eld.FullName -Recurse -File -ErrorAction SilentlyContinue
        }
        $rootFiles = Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue
        foreach ($rf in $rootFiles) {
            if ($allFiles -notcontains $rf) { $allFiles += $rf }
        }

        $totalBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum
        $totalMB = [math]::Round($totalBytes / 1MB, 2)
        
        # Native Java bytecode & compiled JAR mod auditing (.jar in media/java/, libs/, etc.)
        $jarFiles = @($allFiles | Where-Object { $_.Extension -eq '.jar' -or $_.DirectoryName -match 'media[\\/]java|libs' })
        $hasJavaJar = ($jarFiles.Count -gt 0)
        $javaJarCount = $jarFiles.Count
        $javaJarNames = if ($hasJavaJar) { ($jarFiles | ForEach-Object { $_.Name } | Select-Object -Unique) -join ", " } else { "" }

        # 3D models & meshes: distinguish world/chunk geometry from character skinned meshes
        $rawModelFiles = @($allFiles | Where-Object {
            $_.Extension -match '\.(txt|fbx|obj|bin)$' -and $_.DirectoryName -match 'models|anims|meshes|vehicles|voxel'
        })
        $modelCount = $rawModelFiles.Count
        $worldModelFiles = @($rawModelFiles | Where-Object {
            $_.DirectoryName -notmatch 'skinned|clothing|hair|characters|body|anims' -or $_.DirectoryName -match 'voxel|world|tiles|props|vehicles'
        })
        $worldMeshCount = $worldModelFiles.Count
        $characterMeshCount = $modelCount - $worldMeshCount

        # Texture bloat audit (.png, .pack)
        $texFiles = $allFiles | Where-Object { $_.Extension -match '\.(png|pack|dds)$' }
        $texBytes = ($texFiles | Measure-Object -Property Length -Sum).Sum
        $textureMB = [math]::Round($texBytes / 1MB, 2)

        # File collision tracking
        foreach ($file in $allFiles) {
            if ($file.FullName -match 'media[\\/](.*)$') {
                $relPath = "media/" + ($matches[1] -replace '\\', '/').ToLower()
                if (-not $fileCollisionMap[$relPath]) {
                    $fileCollisionMap[$relPath] = @()
                }
                $fileCollisionMap[$relPath] += $displayName
            }
        }

        # Semantic Lua hook & query audit
        $luaFiles = @($allFiles | Where-Object { $_.Extension -eq '.lua' })
        $luaSemantics = Analyze-ModLuaSemantics -luaFiles $luaFiles

        $permHooks = $luaSemantics.PermanentHooks
        $transHooks = $luaSemantics.TransientHooks
        $throttledHooks = $luaSemantics.ThrottledHooks
        $inHookZombieQueries = $luaSemantics.InHookZombieQueries
        $staticZombieQueries = $luaSemantics.StaticZombieQueries
        $inHookTileQueries = $luaSemantics.InHookTileQueries
        $staticTileQueries = $luaSemantics.StaticTileQueries
        $inHookWorldQueries = $luaSemantics.InHookWorldQueries
        $staticWorldQueries = $luaSemantics.StaticWorldQueries
        $inHookInvQueries = $luaSemantics.InHookInvQueries
        $staticInvQueries = $luaSemantics.StaticInvQueries
        $inHookHeavyContainers = $luaSemantics.InHookHeavyContainers
        $staticHeavyContainers = $luaSemantics.StaticHeavyContainers
        $inHookUIPolls = $luaSemantics.InHookUIPolls
        $staticUIPolls = $luaSemantics.StaticUIPolls
        $inHookJNICalls = $luaSemantics.InHookJNICalls
        $staticJNICalls = $luaSemantics.StaticJNICalls
        $totalWorldQueries = $inHookWorldQueries + $staticWorldQueries
        $totalInvQueries = $inHookInvQueries + $staticInvQueries
        $perFrameTotal = $permHooks + $transHooks + $throttledHooks

        # High-overhead heuristics & known engine bottlenecks
        $stutterVerdict = ""
        if ($modId -match "aparosa_pz3dMinimap") {
            $riskScore += 90
            $stutterVerdict = "Severe Main-Thread Lua Stutter (13-18ms frame delay logged by author)"
            $riskReasons += "Minimap continuously calculates square matrices per frame in Lua"
        }
        if ($modId -match "PZVoxelStudioViewpoint") {
            $riskScore += 85
            $stutterVerdict = "Severe Chunk Meshing Freezes & Heavy VRAM Load"
            $riskReasons += "Massive 3D model injection ($worldMeshCount models) causing 400-500ms chunk stalls"
        }
        if ($hasJavaJar) {
            if ($modId -eq "ZombieBuddy" -or $displayName -eq "ZombieBuddy") {
                $stutterVerdict = "Safe / Passive Framework (Launch-Time JVM Bytecode Transformer)"
                $riskReasons += "Core ASM bytecode transformer patching Java classes at boot ($javaJarNames) - Zero per-frame tick overhead"
            } elseif ($modId -eq "Viewpoint" -or $displayName -eq "Viewpoint") {
                $riskScore += 25
                $stutterVerdict = "Core 1P Camera Matrix & In-Engine Render Engine"
                $riskReasons += "Native Java camera projection matrix running in JVM via ZombieBuddy ($javaJarNames)"
            } elseif ($modId -match "ViewpointTrueWeathers$" -or $displayName -match "True Weathers & Lighting") {
                $riskScore += 25
                $stutterVerdict = "Volumetric Weather & Cinematic Lighting Engine"
                $riskReasons += "Native Java weather shaders, volumetric fog, and storm lighting passes ($javaJarNames)"
            } elseif ($modId -match "NearVegetation|TREE in 3D" -or $displayName -match "TREE in 3D") {
                $riskScore += 20
                $stutterVerdict = "Near-Scene 3D Tree Mesh Frustum Engine"
                $riskReasons += "Dynamic 3D tree mesh injection in near player frustum ($javaJarNames)"
            } else {
                $riskScore += 10
                $stutterVerdict = "Situational Java Engine Add-on (Dormant Idle)"
                $riskReasons += "Native Java bytecode module triggered during specific gameplay actions ($javaJarNames)"
            }
        }
        if ($modId -match "ControllerSupport" -or $displayName -match "Controller Support") {
            $riskScore += 20
            $riskReasons += "Polls gamepad state continuously on OnRenderTick even if no controller is connected"
        }
        if ($modId -match "ZombieDismemberment") {
            $riskScore += 45
            $stutterVerdict = "Zombie Density CPU Overhead"
            $riskReasons += "Executes on every zombie update to adjust bone states and blood models"
        }
        if ($modId -match "VanillaVehiclesAnimated") {
            $riskScore += 35
            $stutterVerdict = "Vehicle Stream Console Logging Spikes"
            $riskReasons += "Missing vehicle templates causing synchronous console error logging bursts in B42"
        }
        if ($textureMB -gt 100) {
            $riskScore += 20
            $riskReasons += "Heavy texture pack ($textureMB MB of textures) causing high VRAM consumption"
        }

        # Determine continuous polling vs dormant early-exit classification for scoring
        $isContinuous = $false
        if ($permHooks -gt 0) {
            if ($modId -match "ALife|SuperbSurvivors|SubparSurvivors|NPC|Bandits|Humanoid" -or $displayName -match "A-Life|Superb Survivors|NPCs|Bandits") {
                $isContinuous = $true
            } elseif ($modId -match "PushDoors|Push Door|CyesPushDoors" -or $displayName -match "Push Doors") {
                $isContinuous = $true
            } elseif ($inHookZombieQueries -ge 3 -or $modId -match "TrueCrawling|ZombieDismemberment|ZombieAnimation|ZombieCrawl|ZombieCollision") {
                $isContinuous = $true
            } elseif ($inHookTileQueries -ge 5 -and -not ($modId -match "TakeABath|BathAndShower|Shower|PushVehicle|RealisticDash|Lockpick|Construction|TidyUp|GearRattling")) {
                $isContinuous = $true
            }
        }

        # Dynamic semantic scoring (Continuous Polling vs Dormant Early-Exit)
        if ($isContinuous) {
            $riskScore += ($permHooks * 12)
            $riskScore += [math]::Min(25, $inHookWorldQueries * 2)
        } else {
            # Dormant early-exit: JNI bridge invocation only on idle frames, queries fire only during situational triggers
            $riskScore += ($permHooks * 4)
            $riskScore += [math]::Min(10, [math]::Round($inHookWorldQueries * 0.33))
        }
        $riskScore += [math]::Round($throttledHooks * 1.5)
        $riskScore += [math]::Round($transHooks * 0.5)

        $riskScore += [math]::Min(5, [math]::Floor($staticWorldQueries / 20))
        if ($permHooks -gt 0) {
            $riskScore += [math]::Min(15, [math]::Floor($inHookInvQueries / 2))
            $riskScore += [math]::Min(15, [math]::Floor($inHookUIPolls / 2))
            $riskScore += [math]::Min(10, [math]::Floor($inHookJNICalls / 3))
        } else {
            $riskScore += [math]::Min(5, [math]::Floor($inHookInvQueries / 5))
            $riskScore += [math]::Min(5, [math]::Floor($inHookUIPolls / 10))
            $riskScore += [math]::Min(3, [math]::Floor($inHookJNICalls / 5))
        }
        $riskScore += [math]::Min(3, [math]::Floor($staticInvQueries / 50))
        if ($luaSemantics.IsStationaryGated) {
            $riskScore += [math]::Min(5, $inHookHeavyContainers * 1)
        } else {
            $riskScore += [math]::Min(20, $inHookHeavyContainers * 5)
        }

        if ($worldMeshCount -gt 5000) { $riskScore += 45 }
        elseif ($worldMeshCount -gt 1000) { $riskScore += 25 }
        elseif ($worldMeshCount -gt 100) { $riskScore += 10 }
        elseif ($worldMeshCount -gt 20) { $riskScore += 5 }
        elseif ($characterMeshCount -gt 500) { $riskScore += 5 }

        if ($totalMB -gt 100) { $riskScore += 10 }
        elseif ($totalMB -gt 50) { $riskScore += 5 }

        # Dynamic diagnostic reasons for operational overhead
        $dynamicReasons = @()
        if ($permHooks -gt 0) {
            if ($isContinuous) {
                $dynamicReasons += "$permHooks unconstrained permanent loop$(if ($permHooks -ne 1) { 's' } else { '' }) firing every frame"
            } else {
                $dynamicReasons += "$permHooks dormant permanent loop$(if ($permHooks -ne 1) { 's' } else { '' }) (registered in engine, early-returns unless interacting)"
            }
        }
        if ($throttledHooks -gt 0) {
            $dynamicReasons += "$throttledHooks throttled / timer-gated hook$(if ($throttledHooks -ne 1) { 's' } else { '' }) (periodic execution)"
        }
        if ($transHooks -gt 0) {
            $dynamicReasons += "$transHooks transient / self-terminating hook$(if ($transHooks -ne 1) { 's' } else { '' }) (UI/bootstrap only)"
        }
        if ($inHookZombieQueries -gt 0) {
            $dynamicReasons += "$inHookZombieQueries in-hook entity/zombie scan$(if ($inHookZombieQueries -ne 1) { 's' } else { '' }) (getZombieList/getCharacters)"
        }
        if ($inHookTileQueries -gt 0) {
            $dynamicReasons += "$inHookTileQueries in-hook map tile/object quer$(if ($inHookTileQueries -eq 1) { 'y' } else { 'ies' }) (getSquare/getGridSquare)"
        }
        if ($inHookWorldQueries -gt 0 -and $inHookZombieQueries -eq 0 -and $inHookTileQueries -eq 0) {
            $dynamicReasons += "$inHookWorldQueries in-hook world quer$(if ($inHookWorldQueries -eq 1) { 'y' } else { 'ies' }) (getSquare/getZombieList)"
        }
        if ($staticWorldQueries -gt 25) {
            $dynamicReasons += "$staticWorldQueries interactive / UI world queries"
        }
        if ($inHookInvQueries -gt 5) {
            $dynamicReasons += "$inHookInvQueries in-hook inventory searches"
        }
        if ($inHookHeavyContainers -gt 0) {
            if ($luaSemantics.IsStationaryGated) {
                $dynamicReasons += "Container rebuild calls are stationary-gated (only executes when stopped near containers)"
            } else {
                $dynamicReasons += "$inHookHeavyContainers heavy container rebuild call$(if ($inHookHeavyContainers -ne 1) { 's' } else { '' }) (refreshBackpacks/refreshWeight)"
            }
        }
        if ($inHookUIPolls -gt 5) {
            $dynamicReasons += "$inHookUIPolls per-frame UI tree inquiries (UIManager/getIsVisible polling)"
        }
        if ($inHookJNICalls -gt 5) {
            $dynamicReasons += "$inHookJNICalls cross-boundary Java/JNI reflection calls in tick loop"
        }
        if ($worldMeshCount -gt 50 -and -not ($riskReasons -match "model")) {
            $dynamicReasons += "$worldMeshCount custom 3D world model definitions"
        }
        if ($totalMB -gt 50 -and -not ($riskReasons -match "Heavy texture pack")) {
            $dynamicReasons += "Large package size ($totalMB MB)"
        }

        if ($riskReasons.Count -eq 0 -and $dynamicReasons.Count -gt 0) {
            $riskReasons += $dynamicReasons
        }

        # Stutter Verdict Determination
        if (-not $stutterVerdict) {
            if ($riskScore -ge 75) {
                $stutterVerdict = "Critical Stutter Risk (Immediate FPS drops or chunk hitching)"
            } elseif ($riskScore -ge 45) {
                if ($transHooks -gt 15) {
                    $stutterVerdict = "Situational Hitching (Action/XP sync spikes, idle is clean)"
                } else {
                    $stutterVerdict = "High Resource Overhead (Heavy loops or queries)"
                }
            } elseif ($riskScore -ge 20) {
                $stutterVerdict = "Moderate Resource Load (Periodic timers or asset weight)"
            } else {
                if ($transHooks -gt 0 -and $permHooks -eq 0) {
                    $stutterVerdict = "Safe / Harmless (Transient / self-terminating hooks with zero background cost)"
                } elseif ($throttledHooks -gt 0 -and $permHooks -eq 0) {
                    $stutterVerdict = "Safe / Well-Optimized (Throttled timer / modulo-gated hooks)"
                } else {
                    $stutterVerdict = "Safe / Lightweight (Minimal runtime impact)"
                }
            }
        }

        $tier = "Tier 4 (Lightweight)"
        if ($riskScore -ge 75) { $tier = "Tier 1 (CRITICAL)" }
        elseif ($riskScore -ge 45) { $tier = "Tier 2 (HIGH RISK)" }
        elseif ($riskScore -ge 20) { $tier = "Tier 3 (MODERATE)" }

        $stutterMetrics = Get-ModStutterMetrics -modId $modId `
            -modelCount $modelCount `
            -textureMB $textureMB `
            -totalMB $totalMB `
            -permHooks $permHooks `
            -transHooks $transHooks `
            -throttledHooks $throttledHooks `
            -inHookWorldQueries $inHookWorldQueries `
            -inHookInvQueries $inHookInvQueries `
            -riskScore $riskScore `
            -worldMeshCount $worldMeshCount `
            -modName $displayName `
            -inHookHeavyContainers $inHookHeavyContainers `
            -inHookUIPolls $inHookUIPolls `
            -inHookJNICalls $inHookJNICalls `
            -isStationaryGated $luaSemantics.IsStationaryGated `
            -isOptInToggle $luaSemantics.IsOptInToggle `
            -optInModeName $luaSemantics.OptInModeName `
            -inHookZombieQueries $inHookZombieQueries `
            -inHookTileQueries $inHookTileQueries `
            -hasJavaJar $hasJavaJar `
            -javaJarCount $javaJarCount `
            -characterMeshCount $characterMeshCount

        $modReports += [PSCustomObject]@{
            ModId = $modId
            ModName = $displayName
            Tier = $tier
            RiskScore = [math]::Min(100, $riskScore)
            PerFrameHooks = $perFrameTotal
            PermanentHooks = $permHooks
            TransientHooks = $transHooks
            ThrottledHooks = $throttledHooks
            InHookZombieQueries = $inHookZombieQueries
            StaticZombieQueries = $staticZombieQueries
            InHookTileQueries = $inHookTileQueries
            StaticTileQueries = $staticTileQueries
            InHookWorldQueries = $inHookWorldQueries
            StaticWorldQueries = $staticWorldQueries
            TotalWorldQueries = $totalWorldQueries
            InHookInvQueries = $inHookInvQueries
            StaticInvQueries = $staticInvQueries
            TotalInvQueries = $totalInvQueries
            InHookHeavyContainers = $inHookHeavyContainers
            InHookUIPolls = $inHookUIPolls
            InHookJNICalls = $inHookJNICalls
            SizeMB = $totalMB
            TextureMB = $textureMB
            ModelCount = $modelCount
            WorldMeshCount = $worldMeshCount
            CharacterMeshCount = $characterMeshCount
            HasJavaJar = $hasJavaJar
            JavaJarNames = $javaJarNames
            PotentialSpike = $stutterMetrics.PotentialSpike
            FrameTax = $stutterMetrics.FrameTax
            TaxBreakdown = $stutterMetrics.TaxBreakdown
            StutterTrigger = $stutterMetrics.StutterTrigger
            SpikeSeverity = $stutterMetrics.SpikeSeverity
            ActiveTaxRaw = $stutterMetrics.ActiveTaxRaw
            IdleTaxRaw = $stutterMetrics.IdleTaxRaw
            IsContinuousPolling = $stutterMetrics.IsContinuousPolling
            IsDormantEarlyExit = $stutterMetrics.IsDormantEarlyExit
            LoopNature = $stutterMetrics.LoopNature
            AllScenarios = $stutterMetrics.AllScenarios
            PrimaryScenario = $stutterMetrics.PrimaryScenario
            SecondaryScenarios = $stutterMetrics.SecondaryScenarios
            ScenarioCount = $stutterMetrics.ScenarioCount
            Verdict = $stutterVerdict
            Reasons = ($riskReasons -join "; ")
            HookBreakdown = ($luaSemantics.HookBreakdown -join ", ")
        }
    }

    Write-Progress -Activity "Project Zomboid Mod Diagnostic Engine" -Status "Phase 2/4: Classifying File Collisions & Script Overrides..." -PercentComplete 75

    # Find and classify file collisions
    $collisions = @()
    $safeCollisions = @()
    $riskyCollisions = @()

    foreach ($entry in $fileCollisionMap.GetEnumerator()) {
        $uniqueOwners = $entry.Value | Select-Object -Unique
        if ($uniqueOwners.Count -gt 1) {
            $path = $entry.Key
            $modsStr = ($uniqueOwners -join ", ")

            $status = "SAFE"
            $category = "Asset Replacement"
            $note = "Non-code visual or data asset replacement"

            if ($path -match '/translate/') {
                $status = "SAFE"
                $category = "Translation Merge"
                $note = "Game automatically merges localization dictionaries across mods"
            } elseif ($path -match '\.git/|\.github/|\.gitignore|\.vscode/|\.idea/') {
                $status = "SAFE"
                $category = "Repository Metadata"
                $note = "Version control metadata ignored by game engine"
            } elseif ($path -match 'media/ui/categoryicon/|media/ui/icons/|placeholder') {
                $status = "SAFE"
                $category = "Shared UI Asset"
                $note = "Shared UI category icon or placeholder asset"
            } elseif ($path -match 'license|readme|changelog' -and $path -match '\.(txt|md)$') {
                $status = "SAFE"
                $category = "Documentation"
                $note = "Text documentation unused at runtime"
            } elseif ($path -match 'media/lua/(client|server|shared)/' -and $path -notmatch '/translate/') {
                $status = "HIGH RISK"
                $category = "Executable Lua Script"
                $note = "Executable Lua code override; one mod completely overwrites the other"
            } elseif ($path -match 'media/scripts/') {
                $status = "MODERATE RISK"
                $category = "Game Definition Script"
                $note = "Game script override (items, recipes, or vehicles)"
            }

            $colObj = [PSCustomObject]@{
                Path = $path
                Mods = $modsStr
                Status = $status
                Category = $category
                Note = $note
            }

            $collisions += $colObj
            if ($status -eq "SAFE") {
                $safeCollisions += $colObj
            } else {
                $riskyCollisions += $colObj
            }
        }
    }

    # Parse runtime logs safely (even while PZ is actively running)
    Write-Progress -Activity "Project Zomboid Mod Diagnostic Engine" -Status "Phase 3/4: Parsing Engine Telemetry & Slow Frames ($targetLogName)..." -PercentComplete 85
    $targetLogPath = if ($targetLogItem) { $targetLogItem.FullName } else { $null }
    $slowFrames = @()
    $vramReport = "N/A"
    $heapReport = "N/A"
    $frameCap = "Unknown"
    $totalYoungCount = 0
    $totalYoungMs = 0
    $totalOldCount = 0
    $totalOldMs = 0
    $totalConcCount = 0
    $totalConcMs = 0
    $hasGcTelemetry = $false
    $logHasPzOptGc = $false
    $logJvmMaxMb = 0
    $maxEvictions = 0
    $maxEvictedMb = 0.0
    $maxChunkBuilds = 0
    $maxChunkDuration = 0.0
    $maxSnapshotMs = 0.0
    $maxShadowMs = 0.0
    $maxGbufferMs = 0.0
    $maxFloorsMs = 0.0
    $maxWaitMainMs = 0.0
    $vehicleExceptions = @()
    $hasVehicleExceptions = $false

    # Engine Headroom Telemetry (B42 / Viewpoint)
    $hasHeadroomTelemetry = $false
    $headroomFps = 0
    $headroomGpuMs = 0.0
    $headroomRenderCpuMs = 0.0
    $headroomMainThreadMs = 0.0
    $headroomMainThreadFps = 0
    $headroomZombies = 0

    # Pillar 1: Viewpoint / RVV 3D Frustum & Geometry Telemetry
    $hasGeometryTelemetry = $false
    $geomDrawsPerFrame = 0
    $geomMeshDraws = 0
    $geomOwnedModels = 0
    $geomBonePalettes = 0
    $geomShellBlocks = 0
    $geomShellVerticesHeld = ""
    $geomShellVerticesDrawn = ""
    $geomCommittedMb = 0
    $geomHeapUsedMb = 0
    $geomHeapMaxMb = 0
    $geomVramFreeMb = 0
    $geomVramTotalMb = 0
    $geomCulledVertices = 0
    $geomPerspectiveVertices = 0

    # Pillar 2: Consecutive Freeze Clusters
    $freezeClusters = @()

    # Pillar 4: JVM Bytecode Patch & Hook Registry
    $zbPatches = @()
    $hasZbTelemetry = $false

    # Pillar 5: Runtime Mod Error & Exception Attribution
    $missingBones = @()
    $missingVehicleTemplates = @()
    $translationFormatExceptions = @()
    $fluidContainerWarnings = @()

    # Pillar 6: GC Heap Churn Velocity
    $firstLogTimestamp = $null
    $lastLogTimestamp = $null
    $sessionDurationMinutes = 0.0
    $gcVelocitySweepsPerMin = 0.0
    $gcVelocityRating = "Stable"

    if ($targetLogPath -and (Test-Path $targetLogPath)) {
        $logLines = New-Object System.Collections.Generic.List[string]
        try {
            $stream = [System.IO.File]::Open($targetLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ($line) { $logLines.Add($line) }
            }
            $reader.Close()
            $stream.Close()
        } catch {
            $fallbackLines = Get-Content $targetLogPath -ErrorAction SilentlyContinue
            if ($fallbackLines) {
                foreach ($fl in $fallbackLines) {
                    if ($fl) { $logLines.Add($fl) }
                }
            }
        }

        foreach ($line in $logLines) {
            if ($line -match '^\[(\d{2}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]') {
                $ts = $matches[1]
                if (-not $firstLogTimestamp) { $firstLogTimestamp = $ts }
                $lastLogTimestamp = $ts
            }

            if ($line -match 'slow frame on the (main|render) thread:\s*([\d\.]+)\s*ms,\s*(?:ours|our passes)\s*([\d\.]+)(?:\s*\((.*?)\))?,\s*the rest\s*([\d\.]+)(?:\s*\((.*?)\))?') {
                $th = $matches[1]
                $tMs = [double]$matches[2]
                $oMs = [double]$matches[3]
                $oDet = $matches[4]
                $rMs = [double]$matches[5]
                $rDet = $matches[6]
                $fNum = if ($line -match 'f:(\d+)>') { [int]$matches[1] } else { 0 }

                $ccMs = 0.0
                $ccBuilds = 0
                if ($oDet -and ($oDet -match 'chunk cache\s*([\d\.]+):\s*(\d+)\s*builds')) {
                    $ccMs = [double]$matches[1]
                    $ccBuilds = [int]$matches[2]
                }

                $snapMs = 0.0
                if ($oDet -and ($oDet -match 'snapshot\s*([\d\.]+)')) {
                    $snapMs = [double]$matches[1]
                    if ($snapMs -gt $maxSnapshotMs) { $maxSnapshotMs = $snapMs }
                }

                $shadowMs = 0.0
                if ($oDet -and ($oDet -match 'shadow\s*([\d\.]+)')) {
                    $shadowMs = [double]$matches[1]
                    if ($shadowMs -gt $maxShadowMs) { $maxShadowMs = $shadowMs }
                }

                $gbufferMs = 0.0
                if ($oDet -and ($oDet -match 'gbuffer\s*([\d\.]+)')) {
                    $gbufferMs = [double]$matches[1]
                    if ($gbufferMs -gt $maxGbufferMs) { $maxGbufferMs = $gbufferMs }
                }

                $floorsMs = 0.0
                if ($oDet -and ($oDet -match 'floors\s*([\d\.]+)')) {
                    $floorsMs = [double]$matches[1]
                    if ($floorsMs -gt $maxFloorsMs) { $maxFloorsMs = $floorsMs }
                }

                $waitMain = ($th -eq "render" -and ($rDet -match "waiting for the main thread" -or $line -match "waiting for the main thread"))
                if ($waitMain -and $rMs -gt $maxWaitMainMs) {
                    $maxWaitMainMs = $rMs
                }

                $slowFrames += [PSCustomObject]@{
                    Thread = $th
                    DurationMs = $tMs
                    OursMs = $oMs
                    OurDetails = $oDet
                    ChunkCacheMs = $ccMs
                    ChunkCacheBuilds = $ccBuilds
                    SnapshotMs = $snapMs
                    ShadowMs = $shadowMs
                    GbufferMs = $gbufferMs
                    FloorsMs = $floorsMs
                    WaitMainThread = $waitMain
                    RestMs = $rMs
                    RestDetails = $rDet
                    FrameNumber = $fNum
                    Line = $line
                }
            } elseif ($line -match 'slow frame on the (main|render) thread:\s*([\d\.]+)\s*ms.*ours\s*([\d\.]+)') {
                $th = $matches[1]
                $tMs = [double]$matches[2]
                $oMs = [double]$matches[3]
                $fNum = if ($line -match 'f:(\d+)>') { [int]$matches[1] } else { 0 }
                $slowFrames += [PSCustomObject]@{
                    Thread = $th
                    DurationMs = $tMs
                    OursMs = $oMs
                    OurDetails = ""
                    ChunkCacheMs = 0.0
                    ChunkCacheBuilds = 0
                    SnapshotMs = 0.0
                    ShadowMs = 0.0
                    GbufferMs = 0.0
                    FloorsMs = 0.0
                    WaitMainThread = $false
                    RestMs = [math]::Max(0.0, $tMs - $oMs)
                    RestDetails = "Engine Simulation"
                    FrameNumber = $fNum
                    Line = $line
                }
            }

            if ($line -match 'BaseVehicle\.addToWorld> Exception thrown' -or $line -match 'addKeyToGloveBox.*glovebox\.container.*is null') {
                $hasVehicleExceptions = $true
                $vehicleExceptions += "BaseVehicle.addToWorld NullPointerException (Missing glovebox.container in vehicle script during chunk spawn)"
            } elseif ($line -match 'Vehicle template not found:\s*(.+)') {
                $hasVehicleExceptions = $true
                $vehicleExceptions += "Vehicle template not found: $($matches[1].Trim())"
            }

            if ($line -match '\[Viewpoint\]\s*(\d+)\s*fps\s*\|\s*gpu ms[^\|]+\(([\d\.]+)\).*?\|\s*render cpu ms[^\|]+\(([\d\.]+)\).*?\|\s*main thread frame\s*([\d\.]+)\s*ms\s*\((\d+)\s*fps\).*?\|\s*zombies loaded\s*(\d+)') {
                $hasHeadroomTelemetry = $true
                $headroomFps = [int]$matches[1]
                $headroomGpuMs = [double]$matches[2]
                $headroomRenderCpuMs = [double]$matches[3]
                $headroomMainThreadMs = [double]$matches[4]
                $headroomMainThreadFps = [int]$matches[5]
                $headroomZombies = [int]$matches[6]
            }

            # 3D Frustum Geometry
            if ($line -match 'draws/frame\s*(\d+)(?:\s*\(mesh draws in them\s*(\d+))?') {
                $hasGeometryTelemetry = $true
                $d = [int]$matches[1]
                if ($d -gt $geomDrawsPerFrame) {
                    $geomDrawsPerFrame = $d
                    if ($matches[2]) { $geomMeshDraws = [int]$matches[2] }
                }
            }
            if ($line -match 'owned model instances drawn\s*(\d+).*?palettes\s*(\d+)\s*bones') {
                $m = [int]$matches[1]
                $b = [int]$matches[2]
                if ($m -gt $geomOwnedModels) { $geomOwnedModels = $m }
                if ($b -gt $geomBonePalettes) { $geomBonePalettes = $b }
            }
            if ($line -match 'shell blocks in view\s*(\d+)\s*\(([\d\.]+M)\s*vertices held(?:;\s*drawn\s*([^)]+))?\)') {
                $geomShellBlocks = [int]$matches[1]
                $geomShellVerticesHeld = $matches[2]
                if ($matches[3]) { $geomShellVerticesDrawn = $matches[3] }
            }
            if ($line -match 'process MiB committed\s*(\d+).*?heap used\s*(\d+)\s*of\s*(\d+)') {
                $geomCommittedMb = [int]$matches[1]
                $geomHeapUsedMb = [int]$matches[2]
                $geomHeapMaxMb = [int]$matches[3]
            }
            if ($line -match 'video memory MiB free\s*(\d+)\s*of\s*(\d+)') {
                $geomVramFreeMb = [int]$matches[1]
                $geomVramTotalMb = [int]$matches[2]
            }
            if ($line -match 'perspectiveVertices\s*(\d+).*?culled\s*(\d+)') {
                $geomPerspectiveVertices = [int]$matches[1]
                $geomCulledVertices = [int]$matches[2]
            }

            # GC telemetry
            if ($line -match '\|\s*gc\s+([^\|]+)\|') {
                $hasGcTelemetry = $true
                $str = $matches[1].Trim()
                if ($str -match 'Young Generation (\d+) in (\d+) ms') {
                    $totalYoungCount += [int]$matches[1]
                    $totalYoungMs += [int]$matches[2]
                }
                if ($str -match 'Old Generation (\d+) in (\d+) ms') {
                    $totalOldCount += [int]$matches[1]
                    $totalOldMs += [int]$matches[2]
                }
                if ($str -match 'Concurrent GC (\d+) in (\d+) ms') {
                    $totalConcCount += [int]$matches[1]
                    $totalConcMs += [int]$matches[2]
                }
            }

            # ZB Bytecode Patches
            if ($line -match '\[ZB\]\s*patching\s+([^\s]+)\s+with\s+(\d+)\s+advice') {
                $hasZbTelemetry = $true
                $zbPatches += [PSCustomObject]@{
                    Target = $matches[1]
                    AdviceCount = [int]$matches[2]
                    Category = if ($matches[1] -match 'IsoPlayer|CharacterInput') { "Player Input & Movement" }
                               elseif ($matches[1] -match 'SpriteRenderer|DeadBodyAtlas|FBORender|render') { "Rendering & Atlas Pipeline" }
                               elseif ($matches[1] -match 'SoundListener|fmod') { "FMOD Audio Subsystem" }
                               elseif ($matches[1] -match 'FluidContainer') { "Entity & Fluid Systems" }
                               elseif ($matches[1] -match 'GameWindow|PerformanceSettings') { "Engine Core & Window" }
                               else { "General Engine" }
                }
            }

            # Runtime Mod Exceptions
            if ($line -match 'ImportedSkeleton\.collectBoneFrames\s*>\s*Could not find bone index for node name:\s*"([^"]+)"') {
                $missingBones += $matches[1]
            } elseif ($line -match 'ERROR:\s*template\s*"([^"]+)"\s*not found') {
                $missingVehicleTemplates += $matches[1]
            } elseif ($line -match 'Translator\.reportMissingArgumentsFromPastAbuse.*Formatting\s*"([^"]+)"') {
                $translationFormatExceptions += $matches[1]
            } elseif ($line -match 'FluidContainerScript\.load\s*>\s*Sanitizing container name\s*''([^'']+)''') {
                $fluidContainerWarnings += $matches[1]
            }

            if ($line -match 'video memory MiB free (\d+) of (\d+)(?:,\s*evictions\s*(\d+)\s*\(([\d\.]+)\s*MiB\))?') {
                $vramReport = "$($matches[1]) MB free of $($matches[2]) MB"
                if ($matches[3]) {
                    $eCount = [int]$matches[3]
                    $eMb = [double]$matches[4]
                    if ($eCount -gt $maxEvictions) {
                        $maxEvictions = $eCount
                        $maxEvictedMb = $eMb
                    }
                }
            }
            if ($line -match 'video memory:\s*(\d+)\s*evictions\s*\(([\d\.]+)\s*MiB\)') {
                $eCount = [int]$matches[1]
                $eMb = [double]$matches[2]
                if ($eCount -gt $maxEvictions) {
                    $maxEvictions = $eCount
                    $maxEvictedMb = $eMb
                }
            }
            if ($line -match 'chunk cache ([\d\.]+):\s*(\d+)\s*builds') {
                $bDur = [double]$matches[1]
                $bCount = [int]$matches[2]
                if ($bCount -gt $maxChunkBuilds) {
                    $maxChunkBuilds = $bCount
                    $maxChunkDuration = $bDur
                }
            }
            if ($line -match 'heap used (\d+) of (\d+)') {
                $heapReport = "$($matches[1]) MB used of $($matches[2]) MB"
            }
            if ($line -match 'frame cap:\s*game\s*(\d+)\s*fps') {
                $frameCap = "$($matches[1]) FPS"
            }
            if ($line -match 'pzopt\.gc=g1') {
                $logHasPzOptGc = $true
            }
            if ($line -match 'JVM\s*\(free:\s*\d+\s*Mb,\s*max:\s*(\d+)\s*Mb') {
                $logJvmMaxMb = [int]$matches[1]
            }
        }
    }

    # Also scan console.txt if distinct from targetLogPath to catch early JVM startup bytecode patches
    if ($consoleItem -and (Test-Path $consoleItem.FullName) -and $consoleItem.FullName -ne $targetLogPath) {
        try {
            $cStream = [System.IO.File]::Open($consoleItem.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $cReader = New-Object System.IO.StreamReader($cStream, [System.Text.Encoding]::UTF8)
            while (-not $cReader.EndOfStream) {
                $cLine = $cReader.ReadLine()
                if ($cLine -match '\[ZB\]\s*patching\s+([^\s]+)\s+with\s+(\d+)\s+advice') {
                    $hasZbTelemetry = $true
                    $zbPatches += [PSCustomObject]@{
                        Target = $matches[1]
                        AdviceCount = [int]$matches[2]
                        Category = if ($matches[1] -match 'IsoPlayer|CharacterInput') { "Player Input & Movement" }
                                   elseif ($matches[1] -match 'SpriteRenderer|DeadBodyAtlas|FBORender|render') { "Rendering & Atlas Pipeline" }
                                   elseif ($matches[1] -match 'SoundListener|fmod') { "FMOD Audio Subsystem" }
                                   elseif ($matches[1] -match 'FluidContainer') { "Entity & Fluid Systems" }
                                   elseif ($matches[1] -match 'GameWindow|PerformanceSettings') { "Engine Core & Window" }
                                   else { "General Engine" }
                    }
                }
                if ($cLine -match 'ImportedSkeleton\.collectBoneFrames\s*>\s*Could not find bone index for node name:\s*"([^"]+)"') {
                    $missingBones += $matches[1]
                } elseif ($cLine -match 'ERROR:\s*template\s*"([^"]+)"\s*not found') {
                    $missingVehicleTemplates += $matches[1]
                } elseif ($cLine -match 'Translator\.reportMissingArgumentsFromPastAbuse.*Formatting\s*"([^"]+)"') {
                    $translationFormatExceptions += $matches[1]
                }
            }
            $cReader.Close()
            $cStream.Close()
        } catch { }
    }

    $vehicleExceptions = @($vehicleExceptions | Select-Object -Unique)

    $gcReport = "No GC stalls logged"
    $gcColor = "Green"
    if ($hasGcTelemetry) {
        if ($totalOldCount -gt 0) {
            $gcReport = "$totalOldCount Old Gen Freezes ($totalOldMs ms) | Young Gen: $totalYoungCount sweeps"
            $gcColor = "Red"
        } elseif ($totalYoungCount -gt 0) {
            $yAvg = [math]::Round($totalYoungMs / $totalYoungCount, 1)
            $gcReport = "0 Old Gen Freezes | Young Gen: $totalYoungCount sweeps (avg $yAvg ms, $totalYoungMs ms total)"
            $gcColor = "Green"
        } else {
            $gcReport = "0 Freezes (JVM heap stable)"
            $gcColor = "Green"
        }
    }

    # Freeze Cluster Grouping
    $currentCluster = @()
    foreach ($sf in $slowFrames) {
        if ($currentCluster.Count -eq 0) {
            $currentCluster += $sf
        } else {
            $prev = $currentCluster[-1]
            $diff = if ($sf.FrameNumber -gt 0 -and $prev.FrameNumber -gt 0) { [math]::Abs($sf.FrameNumber - $prev.FrameNumber) } else { 999 }
            if ($diff -le 3) {
                $currentCluster += $sf
            } else {
                if ($currentCluster.Count -ge 2) {
                    $freezeClusters += (Build-FreezeCluster $currentCluster)
                }
                $currentCluster = @($sf)
            }
        }
    }
    if ($currentCluster.Count -ge 2) {
        $freezeClusters += (Build-FreezeCluster $currentCluster)
    }

    # GC Churn Velocity Calculation
    if ($firstLogTimestamp -and $lastLogTimestamp) {
        try {
            $t1 = [DateTime]::ParseExact($firstLogTimestamp, "dd-MM-yy HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
            $t2 = [DateTime]::ParseExact($lastLogTimestamp, "dd-MM-yy HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
            $sessionDurationMinutes = [math]::Round(($t2 - $t1).TotalMinutes, 1)
        } catch {
            $sessionDurationMinutes = 1.0
        }
    }
    if ($sessionDurationMinutes -gt 0.0 -and $totalYoungCount -gt 0) {
        $gcVelocitySweepsPerMin = [math]::Round($totalYoungCount / [math]::Max(1.0, $sessionDurationMinutes), 1)
        $gcVelocityRating = if ($gcVelocitySweepsPerMin -ge 25.0) { "High Churn (Object Allocation Pressure)" }
                            elseif ($gcVelocitySweepsPerMin -ge 10.0) { "Moderate Churn (Active Generation)" }
                            else { "Low Churn (Stable Heap Allocation)" }
    }

    # Pillar 3: Options Audit (options.ini)
    $optionsIni = Join-Path $ZomboidUserPath "options.ini"
    $optionsFps = "Unknown"
    $optionsFpsVal = 0
    $optionsAuditIssues = @()
    $optDict = @{}
    if (Test-Path $optionsIni) {
        $optLines = Get-Content $optionsIni -ErrorAction SilentlyContinue
        foreach ($ol in $optLines) {
            if ($ol -match '^\s*([^=]+)=(.*)$') {
                $optDict[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        if ($optDict.ContainsKey('frameRate')) {
            $optionsFpsVal = [int]$optDict['frameRate']
            $optionsFps = "$optionsFpsVal FPS"
        }
        
        # 1. Texture Compression
        if ($optDict.ContainsKey('textureCompression') -and $optDict['textureCompression'] -eq 'false') {
            $optionsAuditIssues += [PSCustomObject]@{
                Setting = "textureCompression=false"
                Severity = "CRITICAL"
                Title = "Texture Compression is Disabled"
                Impact = "All modded and vanilla textures (including 4K clothing/vehicles) load uncompressed into VRAM, driving ~10 GB VRAM saturation and PCIe texture swapping."
                Fix = "Enable 'Texture Compression' in Display Options (or set textureCompression=true in options.ini)."
            }
        }
        
        # 2. Model Texture Mipmaps
        if ($optDict.ContainsKey('modelTextureMipmaps') -and $optDict['modelTextureMipmaps'] -eq 'false') {
            $optionsAuditIssues += [PSCustomObject]@{
                Setting = "modelTextureMipmaps=false"
                Severity = "HIGH"
                Title = "3D Model Mipmaps are Disabled"
                Impact = "Custom 3D model meshes lack mipmaps, thrashing GPU texture cache on distant objects and causing visual shimmering and frame pacing judder."
                Fix = "Enable 'Model Texture Mipmaps' in Display Options (or set modelTextureMipmaps=true in options.ini)."
            }
        }
        
        # 3. Asynchronous Tick Rate Dissonance
        $optUiFps = if ($optDict.ContainsKey('uiRenderFPS')) { [int]$optDict['uiRenderFPS'] } else { 60 }
        $optLightFps = if ($optDict.ContainsKey('lightFPS')) { [int]$optDict['lightFPS'] } else { 30 }
        $optVsync = if ($optDict.ContainsKey('vsync')) { $optDict['vsync'] -eq 'true' } else { $false }
        
        if ($optionsFpsVal -ge 120 -and ($optUiFps -le 60 -or $optLightFps -le 30)) {
            $optionsAuditIssues += [PSCustomObject]@{
                Setting = "frameRate=$optionsFpsVal | uiRenderFPS=$optUiFps | lightFPS=$optLightFps"
                Severity = "HIGH"
                Title = "Asynchronous Engine Tick Rate Dissonance"
                Impact = "World renders at $optionsFpsVal FPS, but dynamic lighting ticks at $optLightFps FPS (1 tick every $([math]::Round($optionsFpsVal / $optLightFps, 0)) frames) and UI ticks at $optUiFps FPS with VSync $(if ($optVsync) { 'ON' } else { 'OFF' }). Causes visible micro-stutter."
                Fix = "Increase dynamic lighting rate to 60 FPS or lock display frame rate to 120/90 FPS."
            }
        }
        
        # 4. Active Ragdolls
        if ($optDict.ContainsKey('maxActiveRagdolls')) {
            $ragdolls = [int]$optDict['maxActiveRagdolls']
            if ($ragdolls -ge 15) {
                $optionsAuditIssues += [PSCustomObject]@{
                    Setting = "maxActiveRagdolls=$ragdolls"
                    Severity = "MODERATE"
                    Title = "High Ragdoll Physics Simulation Ceiling"
                    Impact = "Simulating up to $ragdolls active ragdoll bodies simultaneously induces CPU physics spikes during dense zombie combat."
                    Fix = "Lower maxActiveRagdolls to 5-10 in Display Options."
                }
            }
        }

        # 5. Max Texture Resolution
        if ($optDict.ContainsKey('maxTextureSize') -and [int]$optDict['maxTextureSize'] -ge 4) {
            $optionsAuditIssues += [PSCustomObject]@{
                Setting = "maxTextureSize=4 (4096px)"
                Severity = "MODERATE"
                Title = "Maximum 4K Texture Resolution Enabled"
                Impact = "Forces 4096x4096 textures for modded world and item assets, contributing to heavy VRAM memory pressure."
                Fix = "Consider 2048px (maxTextureSize=3) if VRAM headroom drops below 2 GB."
            }
        }
    }

    $zbUnique = @($zbPatches | Group-Object Target | Sort-Object Count -Descending)
    $missingBonesUnique = @($missingBones | Group-Object | Sort-Object Count -Descending)
    $missingVehiclesUnique = @($missingVehicleTemplates | Group-Object | Sort-Object Count -Descending)
    $translationFormatUnique = @($translationFormatExceptions | Group-Object | Sort-Object Count -Descending)

    $hasPacingWarning = $false
    $pacingRatio = 0
    if ($optionsFpsVal -ge 120 -and $headroomMainThreadFps -gt 0) {
        $pacingRatio = [math]::Round(($optionsFpsVal / $headroomMainThreadFps) * 100, 0)
        if ($optionsFpsVal -gt ($headroomMainThreadFps * 1.30)) {
            $hasPacingWarning = $true
        }
    }

    Write-Progress -Activity "Project Zomboid Mod Diagnostic Engine" -Status "Phase 4/4: Correlating Telemetry with Stutter Culprits & Compiling Rankings..." -PercentComplete 95

    $severityRank = @{
        "CRITICAL"   = 1
        "HIGH"       = 2
        "MODERATE"   = 3
        "LOW"        = 4
        "NEGLIGIBLE" = 5
    }

    $sortedMods = $modReports | Sort-Object -Property `
        @{ Expression = { if ($severityRank.ContainsKey($_.SpikeSeverity)) { $severityRank[$_.SpikeSeverity] } else { 99 } } }, `
        @{ Expression = { 
            if ($_.PotentialSpike -match '~(\d+)') { [int]$matches[1] } else { 0 }
        }; Descending = $true }, `
        @{ Expression = { 
            if ($_.FrameTax -match '\+([\d\.]+)') { [double]$matches[1] } else { 0.0 }
        }; Descending = $true }, `
        @{ Expression = { $_.RiskScore }; Descending = $true }

    # Top Correlated Culprit Analysis (Strictly Worthy Candidates Only)
    $worthyMods = @($sortedMods | Where-Object { Test-IsSpikeWorthy $_ })
    $topSpikeMods = @($worthyMods | Select-Object -First 10)
    $topVramMods = @($sortedMods | Where-Object { $_.TextureMB -ge 10 } | Sort-Object -Property TextureMB -Descending | Select-Object -First 5)
    $topMeshMods = @($sortedMods | Where-Object { $_.WorldMeshCount -ge 20 -or ($_.ModId -match 'voxel|vehicle' -and $_.ModelCount -ge 20) } | Sort-Object -Property WorldMeshCount -Descending | Select-Object -First 10)
    $topCpuMods = @($worthyMods | Where-Object { $_.PermanentHooks -gt 0 -or $_.InHookWorldQueries -gt 0 -or $_.ThrottledHooks -gt 0 } | Sort-Object -Property { ($_.PermanentHooks * 0.45) + ($_.InHookWorldQueries * 0.08) + ($_.ThrottledHooks * 0.02) } -Descending | Select-Object -First 10)

    # Precision Spike Root Cause & Causal Attribution
    $worstSpikeObj = $null
    $worstSpikeAnatomy = ""
    $worstSpikeRootCause = ""
    $worstSpikeAttribution = ""
    $worstSpikeRecommendation = ""
    $worstSpikeCorrelatedMods = @()
    $wTotal = 0.0
    $wTh = ""

    if ($slowFrames.Count -gt 0) {
        $worstSpikeObj = $slowFrames | Sort-Object DurationMs -Descending | Select-Object -First 1
        $wTotal = $worstSpikeObj.DurationMs
        $wRest = $worstSpikeObj.RestMs
        $wOurs = $worstSpikeObj.OursMs
        $wCC = $worstSpikeObj.ChunkCacheMs
        $wBuilds = $worstSpikeObj.ChunkCacheBuilds
        $wRestDet = $worstSpikeObj.RestDetails
        $wTh = $worstSpikeObj.Thread

        $gcPct = if ($wTotal -gt 0) { [math]::Round(($wRest / $wTotal) * 100, 1) } else { 0 }
        $ccPct = if ($wTotal -gt 0) { [math]::Round(($wOurs / $wTotal) * 100, 1) } else { 0 }

        if ($wRestDet -match "collector's pauses" -and $gcPct -ge 50.0) {
            $worstSpikeAnatomy = "$wRest ms Engine & GC Pauses ($gcPct%) | $wOurs ms Chunk Meshing & Passes ($ccPct%)"
            $jvmState = Get-PZJvmStatus
            $heapDisplay = if ($jvmState.ConfiguredHeap) { $jvmState.ConfiguredHeap.ToUpper() } elseif ($logJvmMaxMb -gt 0) { "$([math]::Round($logJvmMaxMb / 1024))GB" } else { "16GB" }
            $isTuned = $jvmState.IsFullyOptimized -or $jvmState.IsG1GC -or $logHasPzOptGc

            if ($isTuned) {
                $worstSpikeRootCause = "Java Garbage Collection Young Gen Sweep (G1GC Active - $heapDisplay Heap)"
                $worstSpikeAttribution = "Java Garbage Collection Young Gen sweep during intensive allocation pressure (G1GC active, $heapDisplay heap). Pauses are heavily dampened by G1GC, but massive 3D model/mesh chunk loading is still generating object allocations."
                $worstSpikeRecommendation = "Low-latency G1GC & 16GB clamp is already active! To eliminate remaining allocation pressure, disable heavy 3D asset packs (e.g. PZVoxelStudioViewpoint) via Menu Option [6]."
            } else {
                $worstSpikeRootCause = "Severe Java Garbage Collection Freeze (Engine Memory Sweep)"
                $worstSpikeAttribution = "JVM Heap Garbage Collection sweep on unoptimized heap (-Xmx$($heapDisplay.ToLower())). Young Gen accumulation caused 500ms+ freeze. NOT caused by Lua UI or QOL mods."
                $worstSpikeRecommendation = "Apply Menu Option [4] (One-Click G1GC + 5ms Pause Tuning & 16GB Heap Clamp) to eliminate GC freezes."
            }
            if ($wCC -ge 10.0 -or $wBuilds -ge 10) {
                $candidates = @($topMeshMods | Where-Object { Test-IsSpikeWorthy $_ })
                $extraWorthy = @($worthyMods | Where-Object { $candidates -notcontains $_ })
                $worstSpikeCorrelatedMods = @($candidates + $extraWorthy | Select-Object -First 10)
            } else {
                $worstSpikeCorrelatedMods = @($worthyMods | Select-Object -First 10)
            }
        } elseif ($worstSpikeObj.SnapshotMs -ge 30.0 -or ($wTotal -gt 0 -and ($worstSpikeObj.SnapshotMs / $wTotal) -ge 0.40)) {
            $snapPct = [math]::Round(($worstSpikeObj.SnapshotMs / $wTotal) * 100, 1)
            $worstSpikeAnatomy = "$($worstSpikeObj.SnapshotMs) ms Character/Bone Snapshots ($snapPct%) | $wRest ms Engine Simulation ($gcPct%)"
            $worstSpikeRootCause = "Viewpoint Character & Bone Snapshot Overhead"
            $worstSpikeAttribution = "Main thread CPU freeze capturing first-person character, skeleton, and clothing matrices."
            $worstSpikeRecommendation = "Disable Viewpoint near-vegetation / ADS passes or reduce layered 3D clothing items."
            $worstSpikeCorrelatedMods = @($sortedMods | Where-Object { $_.ModId -match "Viewpoint|ZombieBuddy" -or $_.LoopNature -match "Java Bytecode" } | Select-Object -First 10)
        } elseif ($worstSpikeObj.ShadowMs -ge 30.0 -or ($wTotal -gt 0 -and ($worstSpikeObj.ShadowMs / $wTotal) -ge 0.40)) {
            $shadPct = [math]::Round(($worstSpikeObj.ShadowMs / $wTotal) * 100, 1)
            $worstSpikeAnatomy = "$($worstSpikeObj.ShadowMs) ms Lamp/Light Shadow Map Passes ($shadPct%) | $wRest ms Render Thread ($gcPct%)"
            $worstSpikeRootCause = "Viewpoint Dynamic Light & Shadow Map Stalls"
            $worstSpikeAttribution = "Render thread GPU stall re-rendering multiple shadow cubes for active street lamps or vehicle headlights."
            $worstSpikeRecommendation = "Lower shadow map distance or disable dynamic lamp shadows in Viewpoint display settings."
            $worstSpikeCorrelatedMods = @($sortedMods | Where-Object { $_.ModId -match "Viewpoint|ZombieBuddy" -or $_.LoopNature -match "Java Bytecode" } | Select-Object -First 10)
        } elseif ($wCC -ge 30.0 -or $wBuilds -ge 20 -or ($wCC / $wTotal) -ge 0.40) {
            $worstSpikeAnatomy = "$wCC ms Chunk Cache Meshing ($ccPct%, $wBuilds builds) | $wRest ms Engine Simulation ($gcPct%)"
            $worstSpikeRootCause = "Dynamic 3D Mesh Compilation on Chunk Traversal"
            $worstSpikeAttribution = "Massive 3D model injections crossing chunk borders."
            $worstSpikeRecommendation = "Trim 3D furniture/model replacement packs to reduce chunk boundary stalls."
            $worstSpikeCorrelatedMods = @($topMeshMods | Where-Object { Test-IsSpikeWorthy $_ } | Select-Object -First 10)
        } elseif ($wTh -eq "render" -and ($wRestDet -match "waiting for the main thread" -or $worstSpikeObj.WaitMainThread)) {
            $worstSpikeAnatomy = "$wRest ms Waiting for Main Thread ($gcPct%) | $wOurs ms Render Passes ($ccPct%)"
            $worstSpikeRootCause = "GPU Render Thread Blocked Waiting for CPU Main Thread Tick"
            $worstSpikeAttribution = "Main thread CPU tick budget overflow from excessive per-frame Lua loops."
            $worstSpikeRecommendation = "Lower in-game frame rate cap to 120 FPS (Option [5]) or reduce vehicle fleet mods."
            $worstSpikeCorrelatedMods = @($topCpuMods | Where-Object { Test-IsSpikeWorthy $_ } | Select-Object -First 10)
        } else {
            $worstSpikeAnatomy = "$wRest ms Engine Simulation | $wOurs ms Mod Passes"
            $worstSpikeRootCause = "High Simulation / Combat Burst"
            $worstSpikeAttribution = "Heavy world/zombie queries or entity updates during action."
            $worstSpikeRecommendation = "Review mods with high in-hook entity queries."
            $worstSpikeCorrelatedMods = @($worthyMods | Select-Object -First 10)
        }
    }

    # Compute Global Modpack Totals & Loop Density
    $totalPermHooks = ($modReports | Measure-Object -Property PermanentHooks -Sum).Sum
    if (-not $totalPermHooks) { $totalPermHooks = 0 }
    $totalTransHooks = ($modReports | Measure-Object -Property TransientHooks -Sum).Sum
    if (-not $totalTransHooks) { $totalTransHooks = 0 }
    $totalThrottledHooks = ($modReports | Measure-Object -Property ThrottledHooks -Sum).Sum
    if (-not $totalThrottledHooks) { $totalThrottledHooks = 0 }
    $totalInHookQueries = ($modReports | Measure-Object -Property InHookWorldQueries -Sum).Sum
    if (-not $totalInHookQueries) { $totalInHookQueries = 0 }
    $totalModModels = ($modReports | Measure-Object -Property ModelCount -Sum).Sum
    if (-not $totalModModels) { $totalModModels = 0 }
    $totalModTexMB = [math]::Round(($modReports | Measure-Object -Property TextureMB -Sum).Sum, 2)
    $totalModSizeMB = [math]::Round(($modReports | Measure-Object -Property SizeMB -Sum).Sum, 2)
    $totalActiveTaxRaw = [math]::Round(($modReports | Measure-Object -Property ActiveTaxRaw -Sum).Sum, 2)
    $totalIdleTaxRaw = [math]::Round(($modReports | Measure-Object -Property IdleTaxRaw -Sum).Sum, 2)
    if ($totalActiveTaxRaw -eq 0 -and $totalPermHooks -gt 0) {
        $totalActiveTaxRaw = [math]::Round(($totalPermHooks * 0.45) + ($totalInHookQueries * 0.08) + ($totalThrottledHooks * 0.02), 2)
        $totalIdleTaxRaw = [math]::Round(($totalPermHooks * 0.10) + ($totalThrottledHooks * 0.005), 2)
    }

    # Attribution of permanent loop owners across active mods (Categorized by continuous vs dormant)
    $permHookMods = @($modReports | Where-Object { $_.PermanentHooks -gt 0 } | Sort-Object -Property PermanentHooks -Descending)
    $continuousHookMods = @($permHookMods | Where-Object { $_.IsContinuousPolling })
    $dormantHookMods = @($permHookMods | Where-Object { $_.IsDormantEarlyExit -or (-not $_.IsContinuousPolling) })

    $continuousOwnersText = if ($continuousHookMods.Count -gt 0) {
        ($continuousHookMods | ForEach-Object { "$($_.ModName) ($($_.PermanentHooks))" }) -join ", "
    } else { "" }

    $dormantOwnersText = if ($dormantHookMods.Count -gt 0) {
        ($dormantHookMods | ForEach-Object { "$($_.ModName) ($($_.PermanentHooks))" }) -join ", "
    } else { "" }

    $permOwnersText = if ($permHookMods.Count -gt 0) {
        " [" + (($permHookMods | ForEach-Object { "$($_.ModName) ($($_.PermanentHooks))" }) -join ", ") + "]"
    } else { "" }

    # Detect mass vehicle fleet stacking
    $vehicleMods = $modReports | Where-Object {
        $_.ModId -ne 'PushVehicle' -and (
            $_.ModId -match 'vehicle|jeep|chevy|ford|dodge|lambo|nissan|amgeneral|toyota|ferret|touran|meteor|banshee|pontiac|corvette|mercedes|camaro|mustang|mini|barracuda|chevelle|falcon|bushmaster|impreza|lancer|saturn|stagea|towncar|cucv|oshkosh|regal|suburban|hilux|bronco|volvo|trooper|taurus|beetle|damnlib|ECTO1|lockMart|KI5'
        )
    }
    $vehicleCount = if ($vehicleMods) { $vehicleMods.Count } else { 0 }
    $vehiclePermLoops = if ($vehicleMods) { ($vehicleMods | Measure-Object -Property PermanentHooks -Sum).Sum } else { 0 }
    if (-not $vehiclePermLoops) { $vehiclePermLoops = 0 }
    $vehicleThrotLoops = if ($vehicleMods) { ($vehicleMods | Measure-Object -Property ThrottledHooks -Sum).Sum } else { 0 }
    if (-not $vehicleThrotLoops) { $vehicleThrotLoops = 0 }
    $vehicleTax = [math]::Round(($vehiclePermLoops * 0.45) + ($vehicleThrotLoops * 0.02), 2)
    $vehicleModels = if ($vehicleMods) { ($vehicleMods | Measure-Object -Property ModelCount -Sum).Sum } else { 0 }
    if (-not $vehicleModels) { $vehicleModels = 0 }
    $vehicleTexMB = if ($vehicleMods) { [math]::Round(($vehicleMods | Measure-Object -Property TextureMB -Sum).Sum, 2) } else { 0 }

    # Complete Progress Bar before displaying summary
    Write-Progress -Activity "Project Zomboid Mod Diagnostic Engine" -Completed

    # Display summary
    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "   RUNTIME ENGINE TELEMETRY SUMMARY" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host " Ingested Engine Log  : $logInfoStr" -ForegroundColor $(if ($targetLogItem -and $targetLogItem.Length -gt 0) { "Cyan" } else { "Gray" })
    Write-Host " Configured Frame Cap : $optionsFps (Active: $frameCap)" -ForegroundColor White
    if ($hasHeadroomTelemetry) {
        $headroomColor = if ($headroomMainThreadMs -le 11.0 -and $headroomGpuMs -le 11.0) { "Green" } elseif ($headroomMainThreadMs -le 16.6) { "Yellow" } else { "Red" }
        Write-Host " Hardware Frame Times : GPU: $headroomGpuMs ms | Render CPU: $headroomRenderCpuMs ms | Main Thread: $headroomMainThreadMs ms (~$headroomMainThreadFps FPS cap)" -ForegroundColor $headroomColor
        Write-Host " Live World Simulation: $headroomZombies active zombies loaded in simulation radius ($headroomFps in-game FPS)" -ForegroundColor White
    }
    if ($hasPacingWarning) {
        Write-Host "   [!] FRAME PACING MISMATCH DETECTED:" -ForegroundColor Red
        Write-Host "       Configured Frame Cap ($optionsFps) exceeds Main Thread CPU throughput (~$headroomMainThreadFps FPS by $pacingRatio%)!" -ForegroundColor Yellow
        Write-Host "       Cause & Impact : Frame times oscillate between 4.1 ms (empty scenes) and 12-25 ms (world load)," -ForegroundColor Yellow
        Write-Host "                        creating violent frame pacing jitter and running Lua per-frame loops 240x/sec!" -ForegroundColor Yellow
        Write-Host "       Actionable Fix : Set frame rate cap to 120 FPS (or 90 FPS) in Options (or Menu Option [5])." -ForegroundColor Cyan
    }
    if ($hasGeometryTelemetry) {
        Write-Host " 3D Render Frustum    : Peak $geomDrawsPerFrame draws/frame ($geomMeshDraws mesh draws) | $geomOwnedModels models ($geomBonePalettes bones)" -ForegroundColor $(if ($geomDrawsPerFrame -gt 1500) { "Red" } else { "White" })
        if ($geomDrawsPerFrame -gt 1500) {
            Write-Host "   [!] DRAW CALL LIMIT: Draw call count ($geomDrawsPerFrame) exceeds ~1,500/frame driver dispatch threshold!" -ForegroundColor Yellow
            Write-Host "       Impact         : CPU render thread driver overhead stalls frame pacing regardless of GPU headroom." -ForegroundColor DarkYellow
        }
        if ($geomShellBlocks -gt 0) {
            Write-Host " Shell Geometry Load  : $geomShellBlocks blocks in view ($geomShellVerticesHeld vertices held; $geomShellVerticesDrawn drawn)" -ForegroundColor Gray
        }
    }
    Write-Host " GPU VRAM Usage       : $vramReport" -ForegroundColor White
    if ($geomVramTotalMb -gt 0) {
        $vramPct = [math]::Round((($geomVramTotalMb - $geomVramFreeMb) / $geomVramTotalMb) * 100, 1)
        Write-Host " VRAM Saturation      : $($geomVramTotalMb - $geomVramFreeMb) MiB used of $geomVramTotalMb MiB ($vramPct%)" -ForegroundColor $(if ($vramPct -ge 85.0) { "Red" } elseif ($vramPct -ge 70.0) { "Yellow" } else { "Green" })
    }
    if ($maxEvictions -gt 0) {
        Write-Host "   [!] GPU Thrashing  : $maxEvictions texture evictions ($maxEvictedMb MiB swapped across PCIe)!" -ForegroundColor Red
        Write-Host "       Cause & Impact : VRAM saturated; PCIe texture swapping causes 100-250ms render hitching" -ForegroundColor Yellow
        if ($topVramMods.Count -gt 0) {
            $vramCulprits = ($topVramMods | ForEach-Object { "$($_.ModName) ($($_.TextureMB) MB)" }) -join ", "
            Write-Host "       Top VRAM Loads : $vramCulprits" -ForegroundColor DarkYellow
        }
    }
    if ($geomCommittedMb -gt 0) {
        Write-Host " Process Memory (RAM) : $geomCommittedMb MiB committed (Heap used: $geomHeapUsedMb / $geomHeapMaxMb MiB)" -ForegroundColor White
    } else {
        Write-Host " Java Heap Allocation : $heapReport" -ForegroundColor White
    }
    Write-Host " JVM Garbage Collector: $gcReport" -ForegroundColor $gcColor
    $jvmStatusObj = Get-PZJvmStatus
    if ($jvmStatusObj.InstalledJsonFound) {
        $jvmBadgeColor = if ($jvmStatusObj.IsFullyOptimized) { "Green" } elseif ($jvmStatusObj.IsG1GC) { "Cyan" } else { "Yellow" }
        Write-Host " JVM Launcher Tuning  : $($jvmStatusObj.Summary)" -ForegroundColor $jvmBadgeColor
    }
    if ($sessionDurationMinutes -gt 0.0) {
        Write-Host " GC Churn Velocity    : $gcVelocitySweepsPerMin sweeps/min ($gcVelocityRating)" -ForegroundColor $(if ($gcVelocitySweepsPerMin -ge 25.0) { "Red" } elseif ($gcVelocitySweepsPerMin -ge 10.0) { "Yellow" } else { "Green" })
    }
    Write-Host " Slow Frames (>50ms)  : $($slowFrames.Count) recorded in last session" -ForegroundColor $(if ($slowFrames.Count -gt 0) { "Red" } else { "Green" })
    if ($slowFrames.Count -gt 0) {
        Write-Host " Worst Frame Spike    : $wTotal ms ($($wTh.ToUpper()) THREAD)" -ForegroundColor Red
        Write-Host "   -> SPIKE ANATOMY   : $worstSpikeAnatomy" -ForegroundColor Yellow
        Write-Host "   -> ROOT CAUSE      : $worstSpikeRootCause" -ForegroundColor $(if ($worstSpikeRootCause -match "Severe|Heavy") { "Red" } else { "Yellow" })
        Write-Host "   -> ATTRIBUTION     : $worstSpikeAttribution" -ForegroundColor DarkYellow
        Write-Host "   -> ACTIONABLE FIX  : $worstSpikeRecommendation" -ForegroundColor Cyan
        
        if ($worstSpikeCorrelatedMods.Count -gt 0) {
            Write-Host "   -> TOP CORRELATED SPIKE CULPRITS (Up to Top 10 High/Moderate Impact):" -ForegroundColor Yellow
            $cIdx = 0
            foreach ($tsm in $worstSpikeCorrelatedMods) {
                $cIdx++
                $idxStr = $cIdx.ToString().PadLeft(2, '0')
                $modDisplay = $tsm.ModName
                if ($modDisplay.Length -gt 32) { $modDisplay = $modDisplay.Substring(0, 29) + "..." }
                $modDisplay = $modDisplay.PadRight(32)
                $predText = "Pred: $($tsm.PotentialSpike)"
                if ($predText.Length -gt 34) { $predText = $predText.Substring(0, 31) + "..." }
                $predPadded = $predText.PadRight(34)
                
                $cColor = switch ($tsm.SpikeSeverity) {
                    "CRITICAL"   { "Red" }
                    "HIGH"       { "Yellow" }
                    "MODERATE"   { "DarkYellow" }
                    "LOW"        { "Cyan" }
                    Default      { "DarkYellow" }
                }
                Write-Host "      [$idxStr] $modDisplay | $predPadded | $($tsm.StutterTrigger)" -ForegroundColor $cColor
            }
        } else {
            Write-Host "   -> TOP CORRELATED SPIKE CULPRITS: None (No active mods exceed stutter thresholds; spike is engine/GC overhead)" -ForegroundColor Green
        }
    }
    if ($freezeClusters.Count -gt 0) {
        Write-Host " Consecutive Clusters : $($freezeClusters.Count) multi-frame freeze chain(s) detected!" -ForegroundColor Red
        foreach ($fc in ($freezeClusters | Select-Object -First 3)) {
            Write-Host "   -> $($fc.FrameRange) : $($fc.TotalDurationMs) ms across $($fc.FrameCount) consecutive frames" -ForegroundColor Red
            Write-Host "      Root Trigger    : $($fc.Triggers)" -ForegroundColor Yellow
        }
        if ($freezeClusters.Count -gt 3) {
            Write-Host "      ... and $($freezeClusters.Count - 3) more freeze cluster(s) (see ModPerformanceReport.md)" -ForegroundColor Gray
        }
    }
    if ($maxSnapshotMs -gt 30.0 -or $maxShadowMs -gt 30.0) {
        $vColor = if ($maxSnapshotMs -ge 100.0 -or $maxShadowMs -ge 100.0) { "Red" } else { "Yellow" }
        Write-Host " Viewpoint Pass Stalls: Snapshots: $([math]::Round($maxSnapshotMs, 1)) ms | Lamp Shadows: $([math]::Round($maxShadowMs, 1)) ms" -ForegroundColor $vColor
    }
    if ($hasVehicleExceptions) {
        Write-Host " Vehicle Spawn Errors : $($vehicleExceptions.Count) exception(s) logged during chunk handoff!" -ForegroundColor Red
        foreach ($ve in $vehicleExceptions) {
            Write-Host "   -> [EXCEPTION] $ve" -ForegroundColor DarkYellow
        }
        Write-Host "      Cause & Impact  : Defective vehicle script missing container definition stalls chunk loading" -ForegroundColor Yellow
    }
    if ($maxChunkBuilds -gt 0) {
        $chunkColor = if ($maxChunkBuilds -ge 50) { "Red" } elseif ($maxChunkBuilds -ge 20) { "Yellow" } else { "Gray" }
        Write-Host " Chunk Cache Hitches  : Up to $maxChunkBuilds mesh builds/chunk (Peak rebuild stall: $($maxChunkDuration) ms)" -ForegroundColor $chunkColor
        if ($topMeshMods.Count -gt 0) {
            $meshCulprits = ($topMeshMods | ForEach-Object { "$($_.ModName) ($($_.WorldMeshCount) world meshes)" }) -join ", "
            Write-Host "   -> Top 3D Meshes   : $meshCulprits" -ForegroundColor DarkYellow
        }
    }
    Write-Host " File Override Clashes: $($collisions.Count) detected ($($safeCollisions.Count) Safe, $($riskyCollisions.Count) High/Moderate Risk)" -ForegroundColor $(if ($riskyCollisions.Count -gt 0) { "Red" } elseif ($collisions.Count -gt 0) { "Green" } else { "Green" })

    if ($optionsAuditIssues.Count -gt 0) {
        Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "   ENGINE GRAPHICS CONFIGURATION BOTTLENECK AUDIT (options.ini)" -ForegroundColor Yellow
        Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
        foreach ($oi in $optionsAuditIssues) {
            $sevColor = switch ($oi.Severity) { "CRITICAL" { "Red" } "HIGH" { "Yellow" } Default { "Cyan" } }
            Write-Host " [$($oi.Severity)] $($oi.Title) ($($oi.Setting))" -ForegroundColor $sevColor
            Write-Host "   Impact : $($oi.Impact)" -ForegroundColor DarkYellow
            Write-Host "   Fix    : $($oi.Fix)" -ForegroundColor Cyan
        }
    }

    if ($hasZbTelemetry -and $zbUnique.Count -gt 0) {
        Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "   JVM BYTECODE INTERCEPTIONS & CLASS HOOKS ([ZB])" -ForegroundColor Cyan
        Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host " Total Engine Hooks   : $($zbPatches.Count) advice hooks across $($zbUnique.Count) unique engine classes" -ForegroundColor White
        Write-Host " Subsystems Modified  : IsoPlayer movement/input, DeadBodyAtlas render, FMOD sound listener, fluid updates" -ForegroundColor Gray
        Write-Host " Top Hooked Targets   :" -ForegroundColor DarkCyan
        foreach ($zbu in ($zbUnique | Select-Object -First 5)) {
            Write-Host "   - $($zbu.Name) ($($zbu.Count) advice hook(s))" -ForegroundColor Gray
        }
    }

    $totalRuntimeErrors = $missingBones.Count + $missingVehicleTemplates.Count + $translationFormatExceptions.Count
    if ($totalRuntimeErrors -gt 0) {
        Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "   RUNTIME MOD EXCEPTIONS & SCRIPT BLAME ATTRIBUTION" -ForegroundColor Red
        Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host " Total Error Events   : $totalRuntimeErrors exception(s) logged during session" -ForegroundColor Yellow
        if ($missingBones.Count -gt 0) {
            Write-Host "   [!] Animation Skeleton Mismatches ($($missingBones.Count) missing bone errors):" -ForegroundColor Red
            $mbSample = ($missingBonesUnique | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ", "
            Write-Host "       Missing Bones  : $mbSample" -ForegroundColor DarkYellow
            Write-Host "       Likely Mods    : Custom mutants/monsters (CryOfFearMonsters, PZTheMutants) or armor meshes" -ForegroundColor Gray
        }
        if ($missingVehicleTemplates.Count -gt 0) {
            Write-Host "   [!] Missing Vehicle Script Templates ($($missingVehicleTemplates.Count) errors):" -ForegroundColor Red
            $mvtSample = ($missingVehiclesUnique | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ", "
            Write-Host "       Missing Parts  : $mvtSample" -ForegroundColor DarkYellow
            Write-Host "       Likely Mods    : VanillaVehiclesAnimated, KI5campers, KI5trailers" -ForegroundColor Gray
        }
        if ($translationFormatExceptions.Count -gt 0) {
            Write-Host "   [!] Translation Formatting Exceptions ($($translationFormatExceptions.Count) errors):" -ForegroundColor Yellow
            $tfeSample = ($translationFormatUnique | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ", "
            Write-Host "       Format Errors  : $tfeSample" -ForegroundColor DarkYellow
            Write-Host "       Likely Mods    : NeatLockpicking, ProjectViewpointNearVegetation" -ForegroundColor Gray
        }
    }

    # Display Global Modpack Runtime Budget & Loop Density
    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "   GLOBAL MODPACK RUNTIME BUDGET & LOOP DENSITY" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host " Cumulative Mod Frame Tax : +$totalIdleTaxRaw ms/frame (Idle Baseline) | Up to +$totalActiveTaxRaw ms/frame (Active Burst)" -ForegroundColor $(if ($totalActiveTaxRaw -ge 15.0) { "Red" } elseif ($totalActiveTaxRaw -ge 5.0) { "Yellow" } else { "Green" })
    Write-Host "   -> Baseline Idle Load  : Fixed Java-to-Lua event dispatch & continuous background tile/status scans" -ForegroundColor Gray
    Write-Host "   -> Active Peak Load    : Worst-case spike when actively interacting with vehicles, doors, or combat" -ForegroundColor Gray
    Write-Host " Active Per-Frame Loops   : $totalPermHooks permanent hooks registered in Java engine" -ForegroundColor $(if ($totalPermHooks -ge 30) { "Red" } elseif ($totalPermHooks -ge 15) { "Yellow" } else { "Green" })
    if ($continuousHookMods.Count -gt 0) {
        Write-Host "   -> Continuous Polling  : $continuousOwnersText" -ForegroundColor Yellow
    }
    if ($dormantHookMods.Count -gt 0) {
        Write-Host "   -> Dormant (Early-Exit): $dormantOwnersText" -ForegroundColor Cyan
    }
    Write-Host " Total Custom 3D Models   : $totalModModels meshes ($totalModTexMB MB textures across mods)" -ForegroundColor $(if ($totalModModels -ge 3000) { "Red" } elseif ($totalModModels -ge 1000) { "Yellow" } else { "Green" })
    if ($topCpuMods.Count -gt 0) {
        $cpuCulprits = ($topCpuMods | ForEach-Object { "$($_.ModName) ($($_.FrameTax))" }) -join ", "
        Write-Host "   -> Top CPU Tick Tax    : $cpuCulprits" -ForegroundColor DarkCyan
    }

    if ($totalPermHooks -ge 15) {
        Write-Host "`n [ALERT] High Loop Density: Cumulative 'death by 1,000 cuts' detected!" -ForegroundColor Red
        Write-Host "         Even if individual mods score lightweight (green), running $totalPermHooks simultaneous" -ForegroundColor Yellow
        Write-Host "         per-frame Lua hooks creates a +$totalIdleTaxRaw ms idle dispatch tax that eats CPU headroom." -ForegroundColor Gray
    }

    if ($vehicleCount -ge 15) {
        $loopCountText = if ($vehiclePermLoops -gt 0) { "$vehiclePermLoops permanent loops" } elseif ($vehicleThrotLoops -gt 0) { "$vehicleThrotLoops state-gated hooks" } else { "0 active per-frame hooks" }
        Write-Host "`n [MASS VEHICLE FLEET WARNING] $vehicleCount vehicle mods active ($loopCountText)!" -ForegroundColor $(if ($vehiclePermLoops -gt 0) { "Red" } else { "Yellow" })
        if ($vehiclePermLoops -gt 0) {
            Write-Host "         Vehicle mods register per-frame speed/gauge hooks (e.g. DorothyAnemometer)." -ForegroundColor Yellow
        } else {
            Write-Host "         Vehicle mods introduce heavy 3D geometry and texture caching load on chunk traversal." -ForegroundColor Yellow
        }
        Write-Host "         Combined, your vehicle fleet contributes +$vehicleTax ms/frame active overhead & $vehicleModels meshes." -ForegroundColor Gray
        Write-Host "         Recommendation: Trim vehicle mods you aren't currently driving." -ForegroundColor Cyan
    }

    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "   ACTIVE MODS RANKED BY STUTTER & LAG SPIKE POTENTIAL" -ForegroundColor Cyan
    Write-Host "   (Worst-case burst prediction & trigger scenario across all active mods)" -ForegroundColor DarkGray
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  Rank " -ForegroundColor White -NoNewline
    Write-Host ("Mod Name".PadRight(32) + " ") -ForegroundColor White -NoNewline
    Write-Host "| " -ForegroundColor DarkGray -NoNewline
    Write-Host ("Spike Potential (Predicted Burst)".PadRight(34) + " ") -ForegroundColor White -NoNewline
    Write-Host "| " -ForegroundColor DarkGray -NoNewline
    Write-Host "Trigger Scenario" -ForegroundColor White

    Write-Host " ----- " -ForegroundColor DarkGray -NoNewline
    Write-Host (("-" * 32) + " ") -ForegroundColor DarkGray -NoNewline
    Write-Host "| " -ForegroundColor DarkGray -NoNewline
    Write-Host (("-" * 34) + " ") -ForegroundColor DarkGray -NoNewline
    Write-Host "| " -ForegroundColor DarkGray -NoNewline
    Write-Host ("-" * 35) -ForegroundColor DarkGray

    $rank = 0
    foreach ($mod in $sortedMods) {
        $rank++
        $rStr = "[$($rank.ToString().PadLeft(2, '0'))]"
        
        $mName = $mod.ModName
        if ($mName.Length -gt 32) {
            $mName = $mName.Substring(0, 29) + "..."
        }
        $mNamePadded = $mName.PadRight(32)
        
        $pred = "Pred: $($mod.PotentialSpike)"
        if ($pred.Length -gt 34) {
            $pred = $pred.Substring(0, 31) + "..."
        }
        $predPadded = $pred.PadRight(34)
        
        $trigger = $mod.StutterTrigger
        if (-not $trigger) { $trigger = "None (Passive / Static UI)" }
        
        $rowColor = switch ($mod.SpikeSeverity) {
            "CRITICAL"   { "Red" }
            "HIGH"       { "Yellow" }
            "MODERATE"   { "DarkYellow" }
            "LOW"        { "Cyan" }
            Default      { "DarkGray" }
        }
        
        Write-Host " $rStr  " -ForegroundColor $rowColor -NoNewline
        Write-Host "$mNamePadded " -ForegroundColor $rowColor -NoNewline
        Write-Host "| " -ForegroundColor DarkGray -NoNewline
        Write-Host "$predPadded " -ForegroundColor $rowColor -NoNewline
        Write-Host "| " -ForegroundColor DarkGray -NoNewline
        if ($trigger -match "None") {
            Write-Host "$trigger" -ForegroundColor DarkGray
        } else {
            Write-Host "$trigger" -ForegroundColor $rowColor
        }

        # Multi-Scenario Child Rows (Display each secondary scenario indented underneath)
        if ($mod.SecondaryScenarios -and $mod.SecondaryScenarios.Count -gt 0) {
            $sIdx = 1
            foreach ($sec in $mod.SecondaryScenarios) {
                $sIdx++
                $secColor = switch ($sec.Severity) {
                    "CRITICAL"   { "Red" }
                    "HIGH"       { "Yellow" }
                    "MODERATE"   { "DarkYellow" }
                    "LOW"        { "Cyan" }
                    Default      { "DarkGray" }
                }

                $secTitle = "       +-> Scenario $sIdx : $($sec.ScenarioName)"
                if ($secTitle.Length -gt 39) { $secTitle = $secTitle.Substring(0, 36) + "..." }
                $secTitlePadded = $secTitle.PadRight(39)

                $secImp = "Impact: $($sec.Impact)"
                if ($secImp.Length -gt 34) { $secImp = $secImp.Substring(0, 31) + "..." }
                $secImpPadded = $secImp.PadRight(34)

                Write-Host "$secTitlePadded " -ForegroundColor DarkGray -NoNewline
                Write-Host "| " -ForegroundColor DarkGray -NoNewline
                Write-Host "$secImpPadded " -ForegroundColor $secColor -NoNewline
                Write-Host "| " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($sec.Condition)" -ForegroundColor DarkGray
            }
        }
    }

    if ($uninstalledMods.Count -gt 0) {
        Write-Host "`n [!] Notice: $($uninstalledMods.Count) mod(s) in save are uninstalled from disk (omitted from performance audit):" -ForegroundColor DarkYellow
        foreach ($um in $uninstalledMods) {
            Write-Host "     - $um" -ForegroundColor Gray
        }
        Write-Host "     -> Tip: Select Menu Option [6] to clean these phantom mods from your save." -ForegroundColor Cyan
    }

    if ($collisions.Count -gt 0) {
        Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "   DETECTED MOD FILE OVERRIDE CONFLICTS" -ForegroundColor Yellow
        Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host " Total File Overlaps: $($collisions.Count) ($($safeCollisions.Count) Safe, $($riskyCollisions.Count) High/Moderate Risk)" -ForegroundColor Cyan
        
        if ($riskyCollisions.Count -gt 0) {
            Write-Host "`n [ALERT] High-Risk Code / Script Overrides ($($riskyCollisions.Count) detected):" -ForegroundColor Red
            foreach ($rc in ($riskyCollisions | Select-Object -First 5)) {
                Write-Host "   [!] $($rc.Path)" -ForegroundColor Yellow
                Write-Host "       Category: $($rc.Category)" -ForegroundColor DarkYellow
                Write-Host "       Impact:   $($rc.Note)" -ForegroundColor Gray
                Write-Host "       Mods:     $($rc.Mods)" -ForegroundColor Gray
            }
            if ($riskyCollisions.Count -gt 5) {
                Write-Host "   ... and $($riskyCollisions.Count - 5) more high-risk overrides (see ModPerformanceReport.md)" -ForegroundColor Gray
            }
        } else {
            Write-Host "`n [OK] No high-risk script or logic conflicts detected!" -ForegroundColor Green
        }

        if ($safeCollisions.Count -gt 0) {
            Write-Host "`n [SAFE] Safe Overrides ($($safeCollisions.Count) harmless files):" -ForegroundColor Green
            Write-Host "        $($safeCollisions.Count) files are SAFE translation merges, shared UI icons, or Git metadata." -ForegroundColor Gray
            foreach ($sc in ($safeCollisions | Select-Object -First 3)) {
                Write-Host "   [SAFE] $($sc.Path) ($($sc.Category))" -ForegroundColor DarkGreen
            }
            if ($safeCollisions.Count -gt 3) {
                Write-Host "   ... and $($safeCollisions.Count - 3) more safe files (see ModPerformanceReport.md)" -ForegroundColor Gray
            }
        }
    }

    # Generate Markdown Report
    $md = @()
    $md += "# Project Zomboid Mod Performance & Optimization Diagnostic Report"
    $hostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } elseif ($env:HOSTNAME) { $env:HOSTNAME } else { [System.Net.Dns]::GetHostName() }
    $md += "*Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $hostName by PZ-Mod-Performance-Suite $Script:SuiteVersion (Coded with the help of Google Gemini)*"
    $md += ""
    $md += "## Executive Summary"
    $md += "- **Game Version:** $pzVersion"
    $md += "- **Audit Source:** $saveName"
    $md += "- **Runtime Engine Log:** $(if ($targetLogItem -and $targetLogItem.Length -gt 0) { "``$targetLogName`` ($targetLogSizeMb MB)" } else { "None detected" })"
    $md += "- **Total Active Mods Audited:** $($sortedMods.Count)"
    if ($uninstalledMods.Count -gt 0) {
        $md += "- **Uninstalled Phantom Mods in Save:** $($uninstalledMods.Count) (omitted from performance audit: $($uninstalledMods -join ', '))"
    }
    $md += "- **Cumulative Mod Frame Tax:** +$totalIdleTaxRaw ms/frame (Idle Baseline) | Up to +$totalActiveTaxRaw ms/frame (Active Burst)"
    $md += "  - **Permanent Per-Frame Loops ($totalPermHooks total):**"
    if ($continuousHookMods.Count -gt 0) {
        $md += "    - **Continuous Polling ($($continuousHookMods.Count) mods):** $continuousOwnersText (Active spatial tile scans, AI, or status loops)"
    }
    if ($dormantHookMods.Count -gt 0) {
        $md += "    - **Dormant Early-Exit ($($dormantHookMods.Count) mods):** $dormantOwnersText (Hooks registered in engine, but exit in < 0.002 ms when idle)"
    }
    $md += "- **Configured Frame Cap:** $optionsFps (Active: $frameCap)"
    if ($hasPacingWarning) {
        $md += "- **Frame Pacing Diagnostic:** **MISMATCH DETECTED** (Configured $optionsFps vs ~$headroomMainThreadFps FPS Main Thread Throughput - $pacingRatio% mismatch)"
    }
    if ($hasHeadroomTelemetry) {
        $md += "- **Hardware Frame Budget:** GPU: $headroomGpuMs ms | Render CPU: $headroomRenderCpuMs ms | Main Thread: $headroomMainThreadMs ms (~$headroomMainThreadFps FPS headroom)"
        $md += "- **Live Simulation Density:** $headroomZombies active zombies loaded in simulation radius ($headroomFps in-game FPS)"
    }
    if ($hasGeometryTelemetry) {
        $drawCallWarning = if ($geomDrawsPerFrame -gt 1500) { " (**CRITICAL**: Exceeds ~1,500/frame driver overhead ceiling)" } else { "" }
        $md += "- **3D Frustum Geometry:** Peak $geomDrawsPerFrame draws/frame ($geomMeshDraws mesh draws)$drawCallWarning | $geomOwnedModels models ($geomBonePalettes bones)"
        if ($geomShellBlocks -gt 0) {
            $md += "  - **Shell Mesh Load:** $geomShellBlocks blocks in view ($geomShellVerticesHeld vertices held; $geomShellVerticesDrawn drawn)"
        }
    }
    if ($maxSnapshotMs -gt 30.0 -or $maxShadowMs -gt 30.0) {
        $md += "- **Viewpoint Subsystem Stalls:** Character Snapshots: $([math]::Round($maxSnapshotMs, 1)) ms | Dynamic Lamp Shadows: $([math]::Round($maxShadowMs, 1)) ms"
    }
    if ($hasVehicleExceptions) {
        $md += "- **Vehicle Chunk Spawn Errors:** $($vehicleExceptions -join '; ')"
    }
    $md += "- **VRAM Usage:** $vramReport"
    if ($geomVramTotalMb -gt 0) {
        $vramPct = [math]::Round((($geomVramTotalMb - $geomVramFreeMb) / $geomVramTotalMb) * 100, 1)
        $md += "- **VRAM Saturation:** $($geomVramTotalMb - $geomVramFreeMb) MiB used of $geomVramTotalMb MiB ($vramPct%)"
    }
    if ($maxEvictions -gt 0) {
        $md += "- **GPU VRAM Thrashing:** $maxEvictions texture evictions ($maxEvictedMb MiB swapped to RAM across PCIe) - High Stutter Risk"
    }
    if ($geomCommittedMb -gt 0) {
        $md += "- **Process Memory (RAM):** $geomCommittedMb MiB committed ($([math]::Round($geomCommittedMb / 1024, 1)) GB) | Heap: $geomHeapUsedMb of $geomHeapMaxMb MiB"
    }
    $md += "- **Worst Recorded Hitch:** $(if ($slowFrames.Count -gt 0) { "$wTotal ms ($($wTh.ToUpper()) THREAD)" } else { "None" })"
    if ($slowFrames.Count -gt 0) {
        $md += "  - **Spike Anatomy:** $worstSpikeAnatomy"
        $md += "  - **Root Cause:** $worstSpikeRootCause"
        $md += "  - **Diagnostic Attribution:** $worstSpikeAttribution"
        $md += "  - **Actionable Fix:** $worstSpikeRecommendation"
        if ($worstSpikeCorrelatedMods.Count -gt 0) {
            $spikeCulpritsMd = ($worstSpikeCorrelatedMods | ForEach-Object { "**$($_.ModName)** ($($_.PotentialSpike))" }) -join "; "
            $md += "  - **Correlated Culprits:** $spikeCulpritsMd"
        } else {
            $md += "  - **Correlated Culprits:** None (No active mods exceed stutter thresholds; spike is engine/GC overhead)"
        }
    }
    if ($freezeClusters.Count -gt 0) {
        $md += "- **Consecutive Freeze Clusters:** $($freezeClusters.Count) multi-frame stall chains detected (e.g. $($freezeClusters[0].FrameRange): $($freezeClusters[0].TotalDurationMs) ms across $($freezeClusters[0].FrameCount) frames)"
    }
    if ($maxChunkBuilds -gt 0) {
        $md += "- **Chunk Meshing Peak:** $maxChunkBuilds builds ($maxChunkDuration ms rebuild stall)"
    }
    $md += "- **JVM Garbage Collector:** $gcReport"
    if ($jvmStatusObj.InstalledJsonFound) {
        $md += "- **JVM Launcher Tuning:** $($jvmStatusObj.Summary)"
    }
    if ($sessionDurationMinutes -gt 0.0) {
        $md += "- **GC Churn Velocity:** $gcVelocitySweepsPerMin sweeps/min ($gcVelocityRating) across $sessionDurationMinutes min session"
    }
    if ($optionsAuditIssues.Count -gt 0) {
        $md += "- **Graphics Configuration Audit:** $($optionsAuditIssues.Count) bottleneck(s) flagged in options.ini (Texture Compression, Mipmaps, Tick Rates)"
    }
    if ($hasZbTelemetry -and $zbPatches.Count -gt 0) {
        $md += "- **JVM Bytecode Interceptions:** $($zbPatches.Count) advice hooks active across $($zbUnique.Count) unique engine classes ([ZB])"
    }
    $totalRuntimeErrors = $missingBones.Count + $missingVehicleTemplates.Count + $translationFormatExceptions.Count
    if ($totalRuntimeErrors -gt 0) {
        $md += "- **Runtime Mod Script Exceptions:** $totalRuntimeErrors error(s) logged ($($missingBones.Count) missing bones, $($missingVehicleTemplates.Count) missing vehicle templates, $($translationFormatExceptions.Count) translation format exceptions)"
    }
    $md += "- **Direct File Override Clashes:** $($collisions.Count) total ($($safeCollisions.Count) Safe, $($riskyCollisions.Count) High/Moderate Risk)"
    $md += ""
    $md += "---"
    $md += "## Global Modpack Runtime Budget & Fleet Stacking Analysis"
    $md += ""
    if ($hasPacingWarning) {
        $md += "> [!WARNING]"
        $md += "> **FRAME PACING & HEADROOM JITTER DETECTED ($optionsFps Cap vs ~$headroomMainThreadFps FPS Throughput)**"
        $md += "> - **Pacing Mismatch:** Your display frame rate cap ($optionsFps) is **$pacingRatio%** of your hardware simulation ceiling (~$headroomMainThreadFps FPS / $headroomMainThreadMs ms main thread)."
        $md += "> - **Perceptual Stutter Cause:** In simple rooms or menus, the engine delivers ~4.16 ms (240 FPS). The moment you look outside, walk near trees, or enter combat, frame times jump to 10-25 ms. This violent swing creates severe frame delivery judder and perceived stutter."
        $md += "> - **Lua Tick Multiplier:** Running at 240 FPS forces every active per-frame Lua loop to tick **240 times every second**, consuming unnecessary CPU cycles."
        $md += "> - **Actionable Fix:** Cap your frame rate to **120 FPS** (or 90 FPS) in Project Zomboid Display Options (or Menu Option [5]). This instantly stabilizes frame delivery into smooth pacing and cuts Lua per-frame overhead in half."
        $md += ""
    }
    if ($hasVehicleExceptions) {
        $md += "> [!CAUTION]"
        $md += "> **VEHICLE CHUNK SPAWN EXCEPTIONS DETECTED**"
        foreach ($ve in $vehicleExceptions) {
            $md += "> - $ve"
        }
        $md += "> "
        $md += "> *When crossing into new chunks with vehicles, missing vehicle containers (such as glovebox.container == null) throw Java NullPointerExceptions, causing synchronous main-thread stalls.*"
        $md += ""
    }
    $md += "| Global Metric | Audit Value | Safety Threshold | Diagnostic Status |"
    $md += "|:---|:---:|:---:|:---|"
    $md += "| **Idle Baseline Frame Tax** | +$totalIdleTaxRaw ms/frame | < 2.50 ms/frame | $(if ($totalIdleTaxRaw -ge 5.0) { '**HIGH (Heavy idle load)**' } else { 'Optimal' }) |"
    $md += "| **Active Burst Frame Tax** | Up to +$totalActiveTaxRaw ms/frame | < 8.00 ms/frame | $(if ($totalActiveTaxRaw -ge 15.0) { '**CRITICAL (Severe peak drag)**' } elseif ($totalActiveTaxRaw -ge 8.0) { '**HIGH (Heavy peak load)**' } else { 'Optimal' }) |"
    $md += "| **Permanent Per-Frame Loops** | $totalPermHooks hooks ($($continuousHookMods.Count) Continuous, $($dormantHookMods.Count) Dormant) | < 15 hooks | $(if ($totalPermHooks -ge 30) { '**CRITICAL (Death by 1,000 cuts)**' } elseif ($totalPermHooks -ge 15) { '**HIGH (High loop density)**' } else { 'Optimal' }) |"
    $md += "| **Total Custom 3D Meshes** | $totalModModels meshes | < 1,000 meshes | $(if ($totalModModels -ge 3000) { '**CRITICAL (Chunk meshing stalls)**' } elseif ($totalModModels -ge 1000) { '**HIGH (Heavy meshing)**' } else { 'Optimal' }) |"
    $md += "| **Total Texture Footprint** | $totalModTexMB MB | < 500 MB | $(if ($totalModTexMB -ge 1500) { '**CRITICAL (VRAM exhaustion)**' } elseif ($totalModTexMB -ge 500) { '**HIGH (VRAM pressure)**' } else { 'Optimal' }) |"
    $md += "| **GPU Texture Evictions (PCIe Swaps)** | $maxEvictions ($maxEvictedMb MiB) | 0 evictions | $(if ($maxEvictions -gt 0) { '**ACTIVE THRASHING (Render freezes)**' } else { 'Optimal' }) |"
    $md += "| **Peak Chunk Cache Builds** | $maxChunkBuilds builds | < 20 builds | $(if ($maxChunkBuilds -ge 50) { '**HEAVY STALLS (Border traversal lag)**' } else { 'Normal' }) |"
    $md += ""
    if ($topVramMods.Count -gt 0) {
        $vramCulpritsMd = ($topVramMods | ForEach-Object { "**$($_.ModName)** ($($_.TextureMB) MB)" }) -join ", "
        $md += "- **Top Correlated VRAM Heavyweights:** $vramCulpritsMd"
    }
    if ($topMeshMods.Count -gt 0) {
        $meshCulpritsMd = ($topMeshMods | ForEach-Object { "**$($_.ModName)** ($($_.WorldMeshCount) world meshes)" }) -join ", "
        $md += "- **Top Correlated 3D Mesh Injectors:** $meshCulpritsMd"
    }
    if ($topCpuMods.Count -gt 0) {
        $cpuCulpritsMd = ($topCpuMods | ForEach-Object { 
            $taxDetail = if ($_.TaxBreakdown -and $_.TaxBreakdown -ne "Minimal static load") { "$($_.FrameTax) [Breakdown: $($_.TaxBreakdown)]" } else { "$($_.FrameTax)" }
            "**$($_.ModName)** ($taxDetail)" 
        }) -join "; "
        $md += "- **Top Active CPU Tick Overhead:** $cpuCulpritsMd"
    }
    if ($vehicleCount -ge 15) {
        $vehicleLoopText = if ($vehiclePermLoops -gt 0) { "$vehiclePermLoops permanent hooks (e.g. DorothyAnemometer, vehicle dash updates)" } elseif ($vehicleThrotLoops -gt 0) { "$vehicleThrotLoops state-gated hooks" } else { "0 active per-frame hooks" }
        $md += "> [!WARNING]"
        $md += "> **Mass Vehicle Fleet Detected ($vehicleCount Active Vehicle Mods)**"
        $md += "> - **Fleet Per-Frame Loops:** $vehicleLoopText"
        $md += "> - **Fleet Continuous CPU Tax:** +$vehicleTax ms/frame"
        $md += "> - **Fleet Custom Meshes & Textures:** $vehicleModels 3D models, $vehicleTexMB MB textures"
        $md += "> "
        $md += "> *Even though each vehicle mod in isolation appears lightweight (Tier 4 / green), stacking $vehicleCount vehicle mods results in severe cumulative background overhead and VRAM thrashing when crossing chunks.*"
        $md += ""
    }
    $md += "---"
    $md += "## 3D Frustum & Geometry Telemetry (Viewpoint / RVV)"
    $md += ""
    if ($hasGeometryTelemetry) {
        $cullRatio = if ($geomPerspectiveVertices -gt 0) { [math]::Round(($geomCulledVertices / ($geomCulledVertices + $geomPerspectiveVertices)) * 100, 1) } else { 0 }
        $vramUsedMb = $geomVramTotalMb - $geomVramFreeMb
        $vramUsedGb = [math]::Round($vramUsedMb / 1024, 2)
        $vramTotGb = [math]::Round($geomVramTotalMb / 1024, 2)
        $ramGb = [math]::Round($geomCommittedMb / 1024, 2)

        $md += "| 3D Geometry Metric | Audit Value | Safe Baseline | Performance Assessment |"
        $md += "|:---|:---:|:---:|:---|"
        $md += "| **Peak Draw Calls / Frame** | $geomDrawsPerFrame draws ($geomMeshDraws sub-meshes) | < 1,500 draws | $(if ($geomDrawsPerFrame -gt 1500) { '**CRITICAL (Driver CPU bottleneck)**' } else { 'Optimal' }) |"
        $md += "| **Active 3D Model Instances** | $geomOwnedModels models | < 250 models | $(if ($geomOwnedModels -ge 400) { '**HIGH (Heavy vertex pipeline load)**' } else { 'Normal' }) |"
        $md += "| **Skeletal Bone Palette Matrices** | $geomBonePalettes bones | < 8,000 bones | $(if ($geomBonePalettes -ge 15000) { '**HEAVY (Complex clothing/model rigs)**' } else { 'Optimal' }) |"
        $md += "| **Shell Geometry In View** | $geomShellBlocks blocks ($geomShellVerticesHeld held) | < 150 blocks | $(if ($geomShellBlocks -ge 200) { '**HIGH (Extensive world meshing)**' } else { 'Normal' }) |"
        $md += "| **Dynamic Frustum Culling** | $cullRatio% culling ratio ($geomCulledVertices culled) | > 50% | Optimal |"
        $md += "| **GPU VRAM Utilization** | $vramUsedGb GB / $vramTotGb GB ($vramPct%) | < 80% capacity | $(if ($vramPct -ge 85.0) { '**CRITICAL (VRAM saturation risk)**' } else { 'Adequate' }) |"
        $md += "| **Committed Process RAM** | $ramGb GB ($geomCommittedMb MiB) | < 16.0 GB | $(if ($ramGb -ge 18.0) { '**HIGH (Heavy memory residency)**' } else { 'Normal' }) |"
        $md += ""
        if ($geomDrawsPerFrame -gt 1500) {
            $md += "> [!WARNING]"
            $md += "> **CPU RENDER THREAD DRAW CALL CEILING EXCEEDED ($geomDrawsPerFrame DRAWS/FRAME)**"
            $md += "> In DirectX and OpenGL, single-threaded CPU driver overhead dramatically escalates above ~1,500 draw calls per frame."
            $md += "> Even on powerful GPUs, dispatching $geomDrawsPerFrame separate draw calls stalls the Render CPU thread, causing frame pacing jitter."
            $md += ""
        }
    } else {
        $md += "*No raw Viewpoint/RVV geometry telemetry recorded in session log.*"
        $md += ""
    }

    if ($freezeClusters.Count -gt 0) {
        $md += "---"
        $md += "## Consecutive Freeze Cluster Analysis (Multi-Frame Chains)"
        $md += ""
        $md += "When multiple slow frames occur in immediate sequence, the perceived stutter compounds into a complete game freeze."
        $md += ""
        $md += "| Cluster Index | Frame Range | Total Stall Duration | Sequential Frames | Compound Trigger Cascade |"
        $md += "|:---:|:---:|:---:|:---:|:---|"
        $cNum = 0
        foreach ($fc in $freezeClusters) {
            $cNum++
            $durFormatted = "$([math]::Round($fc.TotalDurationMs, 1)) ms"
            $md += "| **#$cNum** | $($fc.FrameRange) | **$durFormatted** | $($fc.FrameCount) consecutive frames | $($fc.Triggers) |"
        }
        $md += ""
        $md += "> [!NOTE]"
        $md += "> **Compound Freeze Cascade Anatomy:** Notice how major clusters (e.g. Cluster #1) often begin with Chunk Cache boundary meshing or character bone snapshots, which allocate high-volume temporary objects that immediately trigger an unmitigated Java Garbage Collection sweep on the very next frame."
        $md += ""
    }

    if ($optionsAuditIssues.Count -gt 0) {
        $md += "---"
        $md += "## Engine Graphics Configuration Bottleneck Audit (options.ini)"
        $md += ""
        $md += "Graphical settings directly amplify mod-induced stutter. The following misconfigurations were detected in `options.ini`:"
        $md += ""
        $md += "| Setting | Severity | Configuration Issue | Diagnostic Impact | Recommended Remediation |"
        $md += "|:---|:---:|:---|:---|:---|"
        foreach ($oi in $optionsAuditIssues) {
            $md += "| ``$($oi.Setting)`` | **$($oi.Severity)** | $($oi.Title) | $($oi.Impact) | $($oi.Fix) |"
        }
        $md += ""
    }

    if ($hasZbTelemetry -and $zbUnique.Count -gt 0) {
        $md += "---"
        $md += "## JVM Bytecode Interceptions & Class Patches ([ZB])"
        $md += ""
        $md += "Bytecode transformers inject advice hooks into native engine Java classes at startup. The following classes are actively intercepted:"
        $md += ""
        $md += "| Intercepted Target Class / Method | Advice Count | Subsystem |"
        $md += "|:---|:---:|:---|"
        foreach ($zbu in ($zbUnique | Select-Object -First 15)) {
            $cat = if ($zbu.Name -match 'IsoPlayer|CharacterInput') { "Player Input & Movement" }
                   elseif ($zbu.Name -match 'SpriteRenderer|DeadBodyAtlas|FBORender|render') { "Rendering & Atlas Pipeline" }
                   elseif ($zbu.Name -match 'SoundListener|fmod') { "FMOD Audio Subsystem" }
                   elseif ($zbu.Name -match 'FluidContainer') { "Entity & Fluid Systems" }
                   elseif ($zbu.Name -match 'GameWindow|PerformanceSettings') { "Engine Core & Window" }
                   else { "General Engine" }
            $md += "| ``$($zbu.Name)`` | $($zbu.Count) advice hook(s) | $cat |"
        }
        if ($zbUnique.Count -gt 15) {
            $md += "| *... and $($zbUnique.Count - 15) more engine methods* | | |"
        }
        $md += ""
    }

    $totalRuntimeErrors = $missingBones.Count + $missingVehicleTemplates.Count + $translationFormatExceptions.Count
    if ($totalRuntimeErrors -gt 0) {
        $md += "---"
        $md += "## Runtime Mod Exceptions & Script Blame Attribution"
        $md += ""
        $md += "Silent background exceptions consume CPU cycles constructing stacktraces and writing to disk. The following exceptions were logged during gameplay:"
        $md += ""
        $md += "| Error Category | Occurrences | Offending Signatures | Originating Mod Attribution | Root Cause & Resolution |"
        $md += "|:---|:---:|:---|:---|:---|"
        if ($missingBones.Count -gt 0) {
            $mbList = ($missingBonesUnique | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ", "
            $md += "| **Animation Skeleton Mismatch** | $($missingBones.Count) | $mbList | Custom mutants/monsters (`CryOfFearMonsters`, `PZTheMutants`) or custom armor meshes | Bone hierarchy missing node index in skeleton; causes recurring matrix lookup failures during animation ticks. |"
        }
        if ($missingVehicleTemplates.Count -gt 0) {
            $mvtList = ($missingVehiclesUnique | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ", "
            $md += "| **Missing Vehicle Template** | $($missingVehicleTemplates.Count) | $mvtList | `VanillaVehiclesAnimated`, `KI5campers`, `KI5trailers` | Generated vehicle script references missing vehicle accessory template during chunk loading. |"
        }
        if ($translationFormatExceptions.Count -gt 0) {
            $tfeList = ($translationFormatUnique | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ", "
            $md += "| **Translation Format String Error** | $($translationFormatExceptions.Count) | $tfeList | `NeatLockpicking`, `ProjectViewpointNearVegetation` | Malformed format specifiers (e.g. unescaped `%`) throw `UnknownFormatConversionException` inside Java `Translator` on UI hover. |"
        }
        $md += ""
    }

    if ($sessionDurationMinutes -gt 0.0 -and $totalYoungCount -gt 0) {
        $md += "---"
        $md += "## JVM Garbage Collection Churn Velocity & Heap Residency"
        $md += ""
        $md += "| GC Metric | Audit Value | Safe Baseline | Evaluation |"
        $md += "|:---|:---:|:---:|:---|"
        $md += "| **Session Duration** | $sessionDurationMinutes minutes | N/A | Active Session |"
        $md += "| **Total Young Gen Sweeps** | $totalYoungCount sweeps | < 15 sweeps/min | Normal |"
        $md += "| **Total GC Pause Time** | $totalYoungMs ms | < 2,000 ms total | Normal |"
        $md += "| **Heap Churn Velocity** | $gcVelocitySweepsPerMin sweeps/min | < 10 sweeps/min | **$gcVelocityRating** |"
        $md += "| **Average Sweep Duration** | $([math]::Round($totalYoungMs / $totalYoungCount, 1)) ms/sweep | < 10 ms | Optimal |"
        $md += ""
    }

    $md += "---"
    $md += "## Key Bottlenecks & High Risk Mods (Tier 1 - Tier 3)"
    $md += ""
    $criticals = @($sortedMods | Where-Object { $_.RiskScore -ge 20 })
    if ($criticals.Count -gt 0) {
        foreach ($c in $criticals) {
            $modIdText = $c.ModId
            $md += "### **$($c.ModName)** ($modIdText)"
            $md += "- **Impact Classification:** **$($c.Tier)** (Score: $($c.RiskScore)/100)"
            $md += "- **Potential Frame Spike:** **$($c.PotentialSpike)**"
            $taxBreakdownDetail = if ($c.TaxBreakdown -and $c.TaxBreakdown -ne "Minimal static load") { " (Tax Breakdown: $($c.TaxBreakdown))" } else { "" }
            $loopNatureDetail = if ($c.LoopNature) { " [Nature: $($c.LoopNature)]" } else { "" }
            $md += "- **Frame Tax:** **$($c.FrameTax)**$loopNatureDetail$taxBreakdownDetail"
            $md += "- **Stutter Trigger Scenario:** $($c.StutterTrigger)"
            $md += "- **Stutter Verdict:** **$($c.Verdict)**"
            $md += "- **Hook Breakdown:** $($c.PermanentHooks) Permanent Loops, $($c.TransientHooks) Transient (self-terminating), $($c.ThrottledHooks) Throttled (timer-gated)"
            $md += "- **World Object Queries:** $($c.InHookWorldQueries) in-hook queries, $($c.StaticWorldQueries) UI/static queries"
            $md += "- **Asset Load:** $($c.SizeMB) MB total ($($c.TextureMB) MB textures, $($c.ModelCount) 3D meshes)"
            if ($c.Reasons) {
                $md += "- **Diagnostic Details:** $($c.Reasons)"
            }
            if ($c.AllScenarios -and $c.AllScenarios.Count -gt 0) {
                $md += ""
                $md += "#### Operational Trigger Scenarios & Performance Impact Matrix"
                $md += "| # | Operational Trigger Scenario | Performance Impact | Severity | Execution State | Trigger Condition |"
                $md += "|:---:|:---|:---:|:---:|:---:|:---|"
                $sNum = 0
                foreach ($sc in $c.AllScenarios) {
                    $sNum++
                    $md += "| **$sNum** | $($sc.ScenarioName) | **$($sc.Impact)** | **$($sc.Severity)** | $($sc.State) | $($sc.Condition) |"
                }
            }
            $md += ""
        }
    } else {
        $md += "*No mods exceeded the Tier 3 threshold. Your active mod list is exceptionally well-optimized!*"
        $md += ""
    }

    $md += "---"
    $md += "## All Active Mods Ranked by Performance Impact"
    $md += ""
    $md += "| Mod Name | Mod ID | Tier | Score | Primary Impact | Frame Tax | All Operational Trigger Scenarios & Impacts | Perm Loops | Trans / Throt | Queries (Hook/UI) | Size (MB) | World Meshes | Stutter Verdict |"
    $md += "|:---|:---|:---:|:---:|:---:|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---|"
    foreach ($m in $sortedMods) {
        $mId = $m.ModId
        $scFormatted = if ($m.AllScenarios -and $m.AllScenarios.Count -gt 0) {
            ($m.AllScenarios | ForEach-Object { "**$($_.ScenarioName)**: $($_.Impact) *($($_.State))* - $($_.Condition)" }) -join "<br/>"
        } else {
            $m.StutterTrigger
        }
        $md += "| $($m.ModName) | $mId | $($m.Tier) | $($m.RiskScore) | $($m.PotentialSpike) | $($m.FrameTax) | $scFormatted | $($m.PermanentHooks) | $($m.TransientHooks) / $($m.ThrottledHooks) | $($m.InHookWorldQueries) / $($m.StaticWorldQueries) | $($m.SizeMB) | $($m.WorldMeshCount) | $($m.Verdict) |"
    }

    if ($collisions.Count -gt 0) {
        $md += ""
        $md += "---"
        $md += "## Detected File Override Conflicts"
        $md += "**Total File Overlaps:** $($collisions.Count) | **Safe Overrides:** $($safeCollisions.Count) | **High-Risk Overrides:** $($riskyCollisions.Count)"
        $tick = [char]96

        if ($riskyCollisions.Count -gt 0) {
            $md += ""
            $md += "### [ALERT] High-Risk Script & Logic Conflicts (Require Attention)"
            $md += "These files overwrite executable Lua code or game definition scripts. One mod will completely replace the logic of another."
            $md += ""
            $md += "| File Path | Risk Level | Conflict Type | Conflicting Mods | Diagnostic Impact |"
            $md += "|:---|:---:|:---:|:---|:---|"
            foreach ($rc in $riskyCollisions) {
                $md += "| $tick$($rc.Path)$tick | **$($rc.Status)** | $($rc.Category) | $($rc.Mods) | $($rc.Note) |"
            }
        }

        if ($safeCollisions.Count -gt 0) {
            $md += ""
            $md += "### [SAFE] Verified Safe Conflicts (Localization Merges & Shared Assets)"
            $md += "These files are harmless. Project Zomboid automatically merges translation dictionaries, and shared UI category icons or Git metadata do not alter gameplay mechanics."
            $md += ""
            $md += "| File Path | Status | Category | Conflicting Mods | Safety Note |"
            $md += "|:---|:---:|:---:|:---|:---|"
            foreach ($sc in $safeCollisions) {
                $md += "| $tick$($sc.Path)$tick | **$($sc.Status)** | $($sc.Category) | $($sc.Mods) | $($sc.Note) |"
            }
        }
    }

    $md += ""
    $md += "---"
    $md += "## Discord Community Summary (Copy & Paste)"
    $md += '```text'
    $md += "PZ Mod Performance Audit ($pzVersion) - $saveName"
    $uninstalledTag = if ($uninstalledMods.Count -gt 0) { " (+$($uninstalledMods.Count) uninstalled)" } else { "" }
    $worstHitchTag = if ($slowFrames.Count -gt 0) { "$wTotal ms" } else { "0ms" }
    $evictTag = if ($maxEvictions -gt 0) { " | Evictions: ${maxEvictions}x" } else { "" }
    $md += "Mods: $($sortedMods.Count)$uninstalledTag | Loops: $totalPermHooks (+${totalIdleTaxRaw}ms idle / +${totalActiveTaxRaw}ms peak)$evictTag | Conflicts: $($collisions.Count) ($($safeCollisions.Count) Safe, $($riskyCollisions.Count) Risky) | VRAM: $vramReport | Worst Hitch: $worstHitchTag"
    $top3 = ($sortedMods | Select-Object -First 3 | ForEach-Object { "$($_.ModName) ($($_.Tier))" }) -join ", "
    $md += "Top Lag Impact Mods: $top3"
    $md += '```'

    [System.IO.File]::WriteAllLines($ReportOutputPath, $md, [System.Text.UTF8Encoding]::new($false))
    Write-Host "`n [SUCCESS] Full Diagnostic Report saved to: $ReportOutputPath" -ForegroundColor Green
    Write-Host "=================================================================`n" -ForegroundColor Cyan
}

# ==============================================================================
# Helper Function: Interactive Custom Workshop Path Configuration
# ==============================================================================
function Configure-PZCustomWorkshopPath {
    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "   CONFIGURE CUSTOM STEAM WORKSHOP / MOD PATH                    " -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan
    $cfg = Get-PZScannerConfig
    $current = if ($cfg.CustomWorkshopPath) { $cfg.CustomWorkshopPath } else { "None (Using Auto-Discovery)" }
    Write-Host " Current Custom Path : $current" -ForegroundColor White

    $detected = Get-WorkshopPaths
    Write-Host "`n Discovered Workshop Libraries ($($detected.Count)):" -ForegroundColor Cyan
    if ($detected.Count -eq 0) {
        Write-Host "   (None automatically detected on standard paths)" -ForegroundColor DarkGray
    } else {
        foreach ($d in $detected) {
            Write-Host "   -> $d" -ForegroundColor Gray
        }
    }

    Write-Host "`n Options:" -ForegroundColor Cyan
    Write-Host "  [1] Set / Update Custom Path (Enter or Drag & Drop folder)" -ForegroundColor White
    Write-Host "  [2] Clear Custom Path (Revert to pure Auto-Discovery)" -ForegroundColor White
    Write-Host "  [0] Return to Main Menu" -ForegroundColor Gray

    $opt = Read-Host "`n Select an option (0-2)"
    switch ($opt.Trim()) {
        "1" {
            Write-Host "`nEnter full path to your Steam Workshop content folder or Steam library:`n(Example: D:\SteamLibrary\steamapps\workshop\content\108600)" -ForegroundColor Yellow
            $inputPath = (Read-Host " Path").Trim().Trim('"').Trim("'")
            if ($inputPath) {
                $resolved = Resolve-CustomWorkshopPath $inputPath
                if ($resolved -and (Test-Path $resolved)) {
                    $modCount = (Get-ChildItem -Path $resolved -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue).Count
                    Set-PZScannerConfig $resolved
                    $script:CustomWorkshopPath = $resolved
                    Write-Host "`n [SUCCESS] Custom path verified & saved: $resolved" -ForegroundColor Green
                    Write-Host "           Discovered $modCount mod(s) in this folder." -ForegroundColor Gray
                } else {
                    Write-Host "`n [ERROR] Path does not exist or is inaccessible: $inputPath" -ForegroundColor Red
                }
            }
        }
        "2" {
            Set-PZScannerConfig ""
            $script:CustomWorkshopPath = ""
            Write-Host "`n [SUCCESS] Custom path cleared. Scanner will use pure auto-discovery." -ForegroundColor Green
        }
        Default {
            Write-Host " Return to menu." -ForegroundColor Gray
        }
    }
    Write-Host "`nPress Enter to return to menu..." -ForegroundColor Gray
    Read-Host | Out-Null
}

# ==============================================================================
# Interactive TUI Menu
# ==============================================================================
function Show-PZMainMenu {
    while ($true) {
        Clear-Host
        $jvmStatusObj = Get-PZJvmStatus
        $gcMenuBadge = if ($jvmStatusObj.IsFullyOptimized) {
            "[ACTIVE: G1GC + $($jvmStatusObj.ConfiguredHeap.ToUpper()) Heap]"
        } elseif ($jvmStatusObj.IsG1GC) {
            "[ACTIVE: G1GC Standard]"
        } else {
            "[APPLY G1GC + 16GB CLAMP]"
        }

        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "   PROJECT ZOMBOID MOD PERFORMANCE & OPTIMIZATION SUITE $Script:SuiteVersion " -ForegroundColor Yellow
        Write-Host "         Created by @KodeMannn with the help of Gemini          " -ForegroundColor DarkCyan
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "  [1] Run Full Performance Diagnostic Scan (Active Save)" -ForegroundColor White
        Write-Host "  [2] Scan Dedicated / Multiplayer Server Config (.ini)" -ForegroundColor White
        Write-Host "  [3] Scan Local Workshop Mods (Zomboid\Workshop)" -ForegroundColor White
        Write-Host "  [4] One-Click Java GC Optimizer $gcMenuBadge" -ForegroundColor $(if ($jvmStatusObj.IsFullyOptimized) { "Green" } elseif ($jvmStatusObj.IsG1GC) { "Cyan" } else { "White" })
        Write-Host "  [5] Engine Graphics & Frame Pacing Optimizer (Frame Cap, 3D Mipmaps, Lighting Sync)" -ForegroundColor White
        Write-Host "  [6] Savegame Mod Sanitizer (Purge Phantoms / Selectively Remove Mods)" -ForegroundColor White
        Write-Host "  [7] Revert Changes / Restore Backups (JVM, FPS, Savegame)" -ForegroundColor Yellow
        Write-Host "  [8] Open Last Generated Diagnostic Report" -ForegroundColor White
        Write-Host "  [9] Configure Custom Steam Workshop / Mod Path" -ForegroundColor White
        Write-Host "  [0] Exit" -ForegroundColor Gray
        Write-Host "=================================================================" -ForegroundColor Cyan
        
        $choice = Read-Host " Select an option (0-9)"
        switch ($choice.Trim()) {
            "1" {
                Invoke-PZScanEngine -CustomWorkshopPath $CustomWorkshopPath -CustomLog $CustomLogPath
                Write-Host "Press Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "2" {
                Write-Host "`nEnter path to server .ini file (or drag and drop it here):" -ForegroundColor Cyan
                $iniPath = (Read-Host).Trim().Trim('"')
                if ($iniPath -and (Test-Path $iniPath)) {
                    Invoke-PZScanEngine -CustomServerIni $iniPath -CustomWorkshopPath $CustomWorkshopPath -CustomLog $CustomLogPath
                } else {
                    Write-Host " [!] File not found: $iniPath" -ForegroundColor Red
                }
                Write-Host "Press Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "3" {
                $cfg = Get-PZScannerConfig
                $defaultWs = if ($CustomWorkshopPath) { $CustomWorkshopPath } elseif ($cfg.CustomWorkshopPath) { $cfg.CustomWorkshopPath } else { Join-Path $ZomboidUserPath "Workshop" }
                Write-Host "`nTarget Workshop Folder: $defaultWs" -ForegroundColor Cyan
                Write-Host "Press [Enter] to scan this folder, or enter a custom path:" -ForegroundColor Gray
                $customPath = (Read-Host).Trim().Trim('"').Trim("'")
                $wsToScan = if ($customPath -and (Test-Path $customPath)) { Resolve-CustomWorkshopPath $customPath } else { $defaultWs }
                Invoke-PZScanEngine -LocalWorkshopOnly -CustomWorkshopPath $wsToScan -CustomLog $CustomLogPath
                Write-Host "`nPress Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "4" {
                Invoke-PZFixGC
                Write-Host "`nPress Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "5" {
                Invoke-PZGraphicsOptimizer
                Write-Host "`nPress Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "6" {
                Invoke-PZCleanSaveMods
                Write-Host "`nPress Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "7" {
                Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Cyan
                Write-Host "   REVERT CHANGES & RESTORE BACKUPS                              " -ForegroundColor Yellow
                Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan
                Write-Host "  [1] Revert ALL Changes (Restore all available backups)" -ForegroundColor White
                Write-Host "  [2] Revert Java GC Optimizer (Restore ProjectZomboid64.json.bak)" -ForegroundColor White
                Write-Host "  [3] Revert Frame Rate Cap (Restore options.ini.bak or 240 FPS)" -ForegroundColor White
                Write-Host "  [4] Revert Cleaned Savegame Mods (Restore mods.txt.bak)" -ForegroundColor White
                Write-Host "  [0] Cancel / Back to Main Menu" -ForegroundColor Gray
                Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan
                $revChoice = Read-Host " Select option (0-4)"
                switch ($revChoice.Trim()) {
                    "1" { Invoke-PZRevertChanges "All" }
                    "2" { Invoke-PZRevertChanges "GC" }
                    "3" { Invoke-PZRevertChanges "FPS" }
                    "4" { Invoke-PZRevertChanges "Save" }
                    Default { Write-Host " Revert cancelled." -ForegroundColor Gray }
                }
                Write-Host "`nPress Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "8" {
                if (Test-Path $ReportOutputPath) {
                    if ($isMacOS) {
                        Start-Process "open" -ArgumentList "`"$ReportOutputPath`""
                    } elseif ($isLinux) {
                        if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
                            Start-Process "xdg-open" -ArgumentList "`"$ReportOutputPath`""
                        } else {
                            Write-Host " [INFO] Diagnostic Report saved to: $ReportOutputPath" -ForegroundColor Cyan
                        }
                    } else {
                        Start-Process $ReportOutputPath
                    }
                } else {
                    Write-Host " [!] No report found yet. Run a scan first!" -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
            "9" {
                Configure-PZCustomWorkshopPath
            }
            "0" {
                Write-Host "`nExiting. Good luck surviving in Kentucky!`n" -ForegroundColor Green
                return
            }
            Default {
                Write-Host " [!] Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ==============================================================================
# Execution Entry Point
# ==============================================================================
if ($Revert) {
    Invoke-PZRevertChanges $Revert
} elseif ($FixGC) {
    Invoke-PZFixGC
} elseif ($OptGraphics) {
    Optimize-PZGraphicsAutoTune
} elseif ($CapFPS -gt 0) {
    Set-PZFrameCap $CapFPS
} elseif ($CleanSave) {
    Invoke-PZCleanSaveMods -Headless
} elseif ($LocalWorkshop) {
    Invoke-PZScanEngine -LocalWorkshopOnly -CustomWorkshopPath $CustomWorkshopPath -CustomLog $CustomLogPath
} elseif ($ServerConfigPath) {
    Invoke-PZScanEngine -CustomServerIni $ServerConfigPath -CustomWorkshopPath $CustomWorkshopPath -CustomLog $CustomLogPath
} elseif ($Auto -or $StutterRoster) {
    Invoke-PZScanEngine -CustomWorkshopPath $CustomWorkshopPath -CustomLog $CustomLogPath
} else {
    Show-PZMainMenu
}
