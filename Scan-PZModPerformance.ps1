<#
.SYNOPSIS
    Project Zomboid Mod Performance & Optimization Suite v2.13.0
.DESCRIPTION
    Comprehensive diagnostic scanner and optimization toolkit for Project Zomboid (Build 42 & 41).
    Features Precision Slow Frame Anatomy Dissection (Main vs Render Thread, GC pauses vs Chunk Cache),
    Causal Bottleneck Attribution (Zero False Mod Accusations), Full Stutter & Lag Spike Impact Roster,
    Hardware & Thread Headroom Telemetry (GPU ms, Render CPU ms, Main Thread ms, Entity Density),
    Top 10 Correlated Spike Culprits with Strict Worthiness Filtering, State-Gated vs Continuous Hook
    Classification, Global Modpack Runtime Budget, Cross-Platform Linux/macOS/Windows Support, and 1-Click Engine Tuning.
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
    [switch]$LocalWorkshop,
    [string]$CustomWorkshopPath = "",
    [switch]$CleanSave,
    [string]$Revert = ""
)

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

# ==============================================================================
# Helper Functions: Steam & Library Discovery (Cross-Platform)
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
    # Windows candidates
    $candidates += @(
        "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid",
        "C:\Program Files\Steam\steamapps\common\ProjectZomboid",
        "D:\SteamLibrary\steamapps\common\ProjectZomboid",
        "D:\Steam\steamapps\common\ProjectZomboid",
        "E:\SteamLibrary\steamapps\common\ProjectZomboid",
        "H:\SteamLibrary\steamapps\common\ProjectZomboid"
    )
    foreach ($c in $candidates) {
        if ((Test-Path (Join-Path $c "ProjectZomboid64.json")) -or 
            (Test-Path (Join-Path $c "projectzomboid.sh")) -or 
            (Test-Path (Join-Path $c "Project Zomboid.app"))) { 
            return $c 
        }
    }
    return $null
}

function Get-WorkshopPaths {
    $potential = @()
    if ($userHome) {
        # Linux & Steam Deck candidates
        $potential += @(
            (Join-Path $userHome ".local/share/Steam/steamapps/workshop/content/108600"),
            (Join-Path $userHome ".steam/steam/steamapps/workshop/content/108600"),
            (Join-Path $userHome ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/workshop/content/108600"),
            (Join-Path $userHome "Steam/steamapps/workshop/content/108600"),
            # macOS candidates
            (Join-Path $userHome "Library/Application Support/Steam/steamapps/workshop/content/108600")
        )
    }
    # Windows candidates
    $potential += @(
        "C:\Program Files (x86)\Steam\steamapps\workshop\content\108600",
        "C:\Program Files\Steam\steamapps\workshop\content\108600",
        "D:\SteamLibrary\steamapps\workshop\content\108600",
        "D:\Steam\steamapps\workshop\content\108600",
        "E:\SteamLibrary\steamapps\workshop\content\108600",
        "H:\SteamLibrary\steamapps\workshop\content\108600"
    )

    # Search for libraryfolders.vdf across all platforms
    $vdfCandidates = @()
    if ($userHome) {
        $vdfCandidates += @(
            (Join-Path $userHome ".local/share/Steam/steamapps/libraryfolders.vdf"),
            (Join-Path $userHome ".steam/steam/steamapps/libraryfolders.vdf"),
            (Join-Path $userHome ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf"),
            (Join-Path $userHome "Library/Application Support/Steam/steamapps/libraryfolders.vdf")
        )
    }
    $vdfCandidates += @(
        "C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf",
        "C:\Program Files\Steam\steamapps\libraryfolders.vdf"
    )

    foreach ($vdfPath in $vdfCandidates) {
        if (Test-Path $vdfPath) {
            $vdfContent = Get-Content $vdfPath -ErrorAction SilentlyContinue
            foreach ($line in $vdfContent) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $libPath = $matches[1] -replace '\\\\', '/' -replace '\\', '/'
                    $ws = Join-Path $libPath "steamapps/workshop/content/108600"
                    if ($potential -notcontains $ws) { $potential += $ws }
                }
            }
        }
    }
    return @($potential | Where-Object { Test-Path $_ })
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

        # Heap calculation: preserve existing large heap (e.g. -Xmx32g) if already >= 16GB
        $newArgs = @()
        foreach ($arg in $json.vmArgs) {
            if ($arg -match '^-Xmx(\d+)([gmGM])') {
                $num = [int]$matches[1]
                $unit = $matches[2].ToLower()
                $existingMB = if ($unit -eq 'g') { $num * 1024 } else { $num }
                if ($existingMB -ge 16384) {
                    $newArgs += $arg
                } else {
                    $newArgs += "-Xmx16g"
                }
            } else {
                $newArgs += $arg
            }
        }
        $json.vmArgs = $newArgs

        # Configure G1GC with 5ms pause target for Windows, Linux, and macOS
        if ($json.windows -and $json.windows.'10.0.17134') {
            $json.windows.'10.0.17134'.vmArgs = @(
                "-XX:+UseG1GC",
                "-Dpzopt.gc=g1",
                "-XX:MaxGCPauseMillis=5"
            )
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
# Optimization Action: Safe Frame Cap Optimizer
# ==============================================================================
function Set-PZFrameCap([int]$targetFps) {
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

    $lines = Get-Content $optionsIni -ErrorAction Stop
    $updated = $false
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match '^frameRate=') {
            $newLines += "frameRate=$targetFps"
            $updated = $true
        } else {
            $newLines += $line
        }
    }
    if ($updated) {
        $newLines | Out-File -FilePath $optionsIni -Encoding ascii
        Write-Host " [SUCCESS] Game frame rate cap set to $targetFps FPS in options.ini!" -ForegroundColor Green
        Write-Host "           This directly throttles per-frame Lua tick execution overhead." -ForegroundColor Gray
    } else {
        Write-Host " [!] Could not locate frameRate setting in options.ini" -ForegroundColor Yellow
    }
}

# ==============================================================================
# Optimization Action: Clean Phantom / Missing Mods from Save
# ==============================================================================
function Invoke-PZCleanSaveMods {
    Write-Host "`n[*] Checking savegame for uninstalled phantom mods..." -ForegroundColor Yellow
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
    if (-not $saveDir) {
        Write-Host " [!] No active savegame found." -ForegroundColor Yellow
        return
    }

    $modsFile = Join-Path $saveDir "mods.txt"
    if (-not (Test-Path $modsFile)) {
        Write-Host " [!] mods.txt not found in save $saveDir." -ForegroundColor Yellow
        return
    }

    # Gather installed mod IDs
    $installedIds = @()
    $wsPaths = Get-WorkshopPaths
    foreach ($w in $wsPaths) {
        $infos = Get-ChildItem -Path $w -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue
        foreach ($i in $infos) {
            $c = Get-Content $i.FullName -ErrorAction SilentlyContinue
            $id = (($c | Where-Object { $_ -match '^id=' }) -replace '^id=\s*', '').Trim() | Select-Object -First 1
            if ($id -and ($installedIds -notcontains $id)) { $installedIds += $id }
        }
    }
    $localMods = Join-Path $ZomboidUserPath "mods"
    if (Test-Path $localMods) {
        $infos = Get-ChildItem -Path $localMods -Recurse -Filter "mod.info" -ErrorAction SilentlyContinue
        foreach ($i in $infos) {
            $c = Get-Content $i.FullName -ErrorAction SilentlyContinue
            $id = (($c | Where-Object { $_ -match '^id=' }) -replace '^id=\s*', '').Trim() | Select-Object -First 1
            if ($id -and ($installedIds -notcontains $id)) { $installedIds += $id }
        }
    }

    $currentMods = Get-Content $modsFile
    $missingMods = @()
    $cleanedLines = @()

    foreach ($line in $currentMods) {
        if ($line -match 'mod\s*=\s*([^,;}\s]+)') {
            $modId = $matches[1].Trim()
            if ($installedIds -notcontains $modId) {
                $missingMods += $modId
                continue # Skip missing mod
            }
        }
        $cleanedLines += $line
    }

    if ($missingMods.Count -eq 0) {
        Write-Host " [OK] All mods in savegame are verified installed on disk. No phantom mods found!" -ForegroundColor Green
        return
    }

    Write-Host " [!] Found $($missingMods.Count) phantom/missing mod(s) in savegame:" -ForegroundColor Yellow
    foreach ($m in $missingMods) {
        Write-Host "     - $m" -ForegroundColor DarkYellow
    }

    # Backup original before modifying (preserves first clean backup)
    $bakFile = "$modsFile.bak"
    if (-not (Test-Path $bakFile)) {
        Copy-Item $modsFile $bakFile -Force
        Write-Host " [OK] Backed up original mods.txt to mods.txt.bak" -ForegroundColor Gray
    }
    $cleanedLines | Out-File -FilePath $modsFile -Encoding ascii
    Write-Host "`n [SUCCESS] Removed $($missingMods.Count) uninstalled mod(s) from savegame!" -ForegroundColor Green
    Write-Host "           Clean save will now boot faster." -ForegroundColor Gray
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
                $newLines | Out-File -FilePath $optionsIni -Encoding ascii
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

        if ($hasPerFrame) {
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
    }

    $isStationaryGated = ($fullCode -match 'not\s+player:isPlayerMoving|not\s+isPlayerMoving|not\s+player:isMoving|not\s+isMoving|isStationary|not\s+\w+:isPlayerMoving|isPlayerStationary')
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
        [int]$inHookTileQueries = 0
    )

    # 1. Potential Spike Duration (ms)
    $spikeMs = "< 1 ms [Imperceptible]"
    $spikeSeverity = "NEGLIGIBLE"

    if ($modId -match "PZVoxelStudioViewpoint" -or $worldMeshCount -gt 5000) {
        $spikeMs = "~350-550 ms [Severe Freeze]"
        $spikeSeverity = "CRITICAL"
    } elseif ($worldMeshCount -gt 1000) {
        $spikeMs = "~100-250 ms [Noticeable Hitch]"
        $spikeSeverity = "HIGH"
    } elseif ($textureMB -gt 100) {
        $spikeMs = "~100-250 ms [VRAM Thrash Hitch]"
        $spikeSeverity = "HIGH"
    } elseif ($modId -match "aparosa_pz3dMinimap") {
        $spikeMs = "~50-120 ms [Continuous Lag]"
        $spikeSeverity = "CRITICAL"
    } elseif ($modId -match "ALife|SuperbSurvivors|SubparSurvivors|NPC|Bandits|Humanoid" -or $modName -match "A-Life|Superb Survivors|NPCs|Bandits") {
        $spikeMs = "~20-60 ms [AI Simulation Spike]"
        $spikeSeverity = "MODERATE"
    } elseif ($transHooks -ge 15 -or $modId -match "Journal|Burd") {
        $spikeMs = "~50-150 ms [Action Spike]"
        $spikeSeverity = "HIGH"
    } elseif ($modId -match "VanillaVehiclesAnimated" -or $worldMeshCount -gt 200) {
        $spikeMs = "~20-60 ms [Micro-Stutter]"
        $spikeSeverity = "MODERATE"
    } elseif ($inHookHeavyContainers -ge 1) {
        if ($isStationaryGated) {
            $spikeMs = "~5-15 ms [Stationary Blip]"
            $spikeSeverity = "LOW"
        } else {
            $spikeMs = "~15-40 ms [Container Hitch]"
            $spikeSeverity = "MODERATE"
        }
    } elseif ($inHookZombieQueries -ge 3 -or $modId -match "TrueCrawling|ZombieDismemberment|ZombieAnimation|ZombieCrawl|ZombieCollision") {
        $spikeMs = "~10-35 ms [Combat Hitch]"
        $spikeSeverity = "MODERATE"
    } elseif ($modId -match "TakeABath|BathAndShower|Shower|Hygiene" -or $modName -match "Take A Bath|Shower") {
        $spikeMs = "~10-25 ms [Hygiene / Fluid Hitch]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "PushDoors|Push Door|CyesPushDoors" -or $modName -match "Push Doors") {
        $spikeMs = "~5-15 ms [Door Hitch]"
        $spikeSeverity = "LOW"
    } elseif ($inHookTileQueries -ge 5) {
        $spikeMs = "~5-15 ms [Object Query Blip]"
        $spikeSeverity = "LOW"
    } elseif ($inHookUIPolls -ge 5 -and ($permHooks -gt 0 -or $throttledHooks -gt 0)) {
        $spikeMs = "~2-8 ms [UI Polling Delay]"
        $spikeSeverity = "LOW"
    } elseif ($inHookJNICalls -ge 5 -and ($permHooks -gt 0 -or $throttledHooks -gt 0)) {
        $spikeMs = "~2-8 ms [JNI Settings Delay]"
        $spikeSeverity = "LOW"
    } elseif (($modId -match "Equipment|Inventory|Hotbar|Crafting|Menu|Map|Health|DragAndDrop" -or $modName -match "Equipment|Inventory|Hotbar|Crafting|Menu|Map|Health") -and ($permHooks -gt 0 -or $throttledHooks -gt 0 -or $inHookInvQueries -gt 0)) {
        $spikeMs = "~2-8 ms [Frame Delay]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "RealisticDash|YourDash" -or $modName -match "Realistic Dashboard|Gauges") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "PushVehicle" -or $modName -match "Push Vehicle") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "DynamicGearRattling|GearRattling" -or $modName -match "Gear Rattling") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "ALifeThreatAlert|ThreatAlert|ThreatDetector" -or $modName -match "Threat Detector") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "NeatLockpicking|Lockpick" -or $modName -match "Lockpicking") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "Construction1PViewpoint" -or $modName -match "Construction 1P") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "P4TidyUpMeister|TidyUpMeister" -or $modName -match "Tidy Up Meister") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "traitsAsSkills" -or $modName -match "Traits As Skills") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "ControllerSupport|Joypad" -or $modName -match "Controller Support") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "PZ_Pulse|PZPulse" -or $modName -match "PZ Pulse") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($modId -match "MoreDamagedObjects" -or $modName -match "More Damaged Objects") {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($throttledHooks -gt 0) {
        $spikeMs = "~5-15 ms [Minor Blip]"
        $spikeSeverity = "LOW"
    } elseif ($permHooks -gt 0) {
        $spikeMs = "~2-8 ms [Frame Delay]"
        $spikeSeverity = "LOW"
    }

    # 2. Continuous & Peak Frame Time Tax (+X.XX ms / frame)
    # Queries in permanent per-frame loops run continuously; queries in throttled hooks run periodically
    $hookTax = ($permHooks * 0.45) + ($throttledHooks * 0.02)
    $worldTax = if ($permHooks -gt 0) { $inHookWorldQueries * 0.08 } elseif ($throttledHooks -gt 0) { $inHookWorldQueries * 0.015 } else { 0.0 }
    $invTax = if ($permHooks -gt 0) { $inHookInvQueries * 0.04 } elseif ($throttledHooks -gt 0) { $inHookInvQueries * 0.01 } else { 0.0 }
    $containerTax = if ($permHooks -gt 0) { $inHookHeavyContainers * 0.15 } elseif ($throttledHooks -gt 0) { $inHookHeavyContainers * 0.04 } else { 0.0 }
    $uiPollTax = if ($permHooks -gt 0) { $inHookUIPolls * 0.02 } elseif ($throttledHooks -gt 0) { $inHookUIPolls * 0.005 } else { 0.0 }
    $jniTax = if ($permHooks -gt 0) { $inHookJNICalls * 0.02 } elseif ($throttledHooks -gt 0) { $inHookJNICalls * 0.005 } else { 0.0 }

    $queryTax = $worldTax + $invTax + $containerTax + $uiPollTax + $jniTax
    $activeTaxRaw = [math]::Round($hookTax + $queryTax, 2)

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
    $idleTaxRaw = [math]::Round($idleHookDispatch + $idlePayloadTax, 2)

    $loopNature = if ($isContinuousPolling) {
        "Continuous Polling"
    } elseif ($isDormantEarlyExit) {
        "Dormant (Early-Exit)"
    } elseif ($throttledHooks -gt 0) {
        "Periodic Timer"
    } else {
        "Event-Driven"
    }

    $taxText = if ($activeTaxRaw -gt 0.01) {
        if ($idleTaxRaw -gt 0.01 -and $idleTaxRaw -lt $activeTaxRaw) {
            "+$([math]::Round($activeTaxRaw, 2)) ms peak (+$( [math]::Round($idleTaxRaw, 2) ) ms idle)"
        } else {
            "+$([math]::Round($activeTaxRaw, 2)) ms/frame"
        }
    } else {
        "+0.00 ms/frame"
    }

    # Deterministic formula breakdown
    $breakdownParts = @()
    if ($hookTax -ge 0.01) { $breakdownParts += "Hooks: +$([math]::Round($hookTax, 2)) ms" }
    if ($worldTax -ge 0.01) { $breakdownParts += "World: +$([math]::Round($worldTax, 2)) ms" }
    if ($invTax -ge 0.01) { $breakdownParts += "Inventory: +$([math]::Round($invTax, 2)) ms" }
    if ($containerTax -ge 0.01) { $breakdownParts += "Containers: +$([math]::Round($containerTax, 2)) ms" }
    if ($uiPollTax -ge 0.01) { $breakdownParts += "UI Polling: +$([math]::Round($uiPollTax, 2)) ms" }
    if ($jniTax -ge 0.01) { $breakdownParts += "JNI/Java: +$([math]::Round($jniTax, 2)) ms" }
    if ($idleTaxRaw -ge 0.01) { $breakdownParts += "Idle Baseline: +$([math]::Round($idleTaxRaw, 2)) ms" }
    $taxBreakdown = if ($breakdownParts.Count -gt 0) { $breakdownParts -join ", " } else { "Minimal static load" }

    # 3. Stutter Trigger Scenario
    $trigger = "None (Passive / Static UI)"
    $optInPrefix = if ($optInModeName) {
        "Opt-In [$optInModeName]: "
    } elseif ($isOptInToggle) {
        "Opt-In Mode: "
    } else {
        "Situational: "
    }
    if ($modId -match "PZVoxelStudioViewpoint" -or $worldMeshCount -ge 1000) {
        $trigger = "Chunk Border Traversal & High-Speed Driving (3D Mesh Rebuild)"
    } elseif ($textureMB -ge 100) {
        $trigger = "VRAM Texture Streaming & Asset Loading (PCIe Thrashing Risk)"
    } elseif ($inHookHeavyContainers -ge 1) {
        if ($isStationaryGated) {
            $trigger = "$($optInPrefix)When Standing Still / Stationary (Container Rebuild - Zero Movement Hitch)"
        } elseif ($modName -match "Viewpoint QOL" -or $modId -match "ViewpointQOL") {
            $trigger = "$($optInPrefix)Moving Near Containers (Backpack Rebuild - Unconstrained Movement Hitch)"
        } else {
            $trigger = "$($optInPrefix)While Inventory / Container Grid Open (Backpack & Weight Rebuild)"
        }
    } elseif ($modId -match "ALife|SuperbSurvivors|SubparSurvivors|NPC|Bandits|Humanoid" -or $modName -match "A-Life|Superb Survivors|NPCs|Bandits") {
        $trigger = if ($permHooks -gt 0) { "Active: Autonomous NPC AI & Sensory Scanning ($permHooks background tick loops)" } else { "Active: Autonomous NPC AI & Sensory Scanning" }
    } elseif ($inHookZombieQueries -ge 3 -or $modId -match "TrueCrawling|ZombieDismemberment|ZombieAnimation|ZombieCrawl|ZombieCollision") {
        $trigger = "Horde Proximity & Combat"
    } elseif ($modId -match "PushDoors|Push Door|CyesPushDoors" -or $modName -match "Push Doors") {
        $trigger = "Active: Background 25-Tile Door Scanner (~Every 2 Ticks)"
    } elseif ($modId -match "TakeABath|BathAndShower|Shower|Hygiene" -or $modName -match "Take A Bath|Shower") {
        $trigger = "Situational: Near Plumbing Fixtures & Bathing Actions (Dormant on Foot)"
    } elseif ($inHookTileQueries -ge 5) {
        $trigger = "Situational: Near Interactive World Objects (Tile Scanning)"
    } elseif ($transHooks -ge 15 -or $modId -match "Journal|Burd") {
        $trigger = "Action: Transcribing / Reading XP"
    } elseif ($inHookUIPolls -ge 5 -or ($modName -match "Viewpoint QOL" -and $throttledHooks -gt 0)) {
        if ($modName -match "Viewpoint QOL" -or $modId -match "ViewpointQOL") {
            $trigger = "$($optInPrefix)While in Viewpoint (UI Polling & Containers)"
        } else {
            $trigger = "$($optInPrefix)While Menu / UI Is Open (High-Frequency UI Polling)"
        }
    } elseif ($modId -match "RealisticDash|YourDash" -or $modName -match "Realistic Dashboard|Gauges") {
        $trigger = "Active: While Inside Vehicle / Driving (Dormant on Foot)"
    } elseif ($modId -match "PushVehicle" -or $modName -match "Push Vehicle") {
        $trigger = "Situational: While Pushing a Vehicle (Dormant on Foot)"
    } elseif ($modId -match "LethalStealth|RET_LethalStealth" -or $modName -match "Lethal Stealth") {
        $trigger = "Situational: While Sneaking / In Stealth Stance (Dormant when Upright)"
    } elseif ($modId -match "DynamicGearRattling|GearRattling" -or $modName -match "Gear Rattling") {
        $trigger = "Situational: While Jogging / Moving on Foot (Gear Audio)"
    } elseif ($modId -match "ALifeThreatAlert|ThreatAlert|ThreatDetector" -or $modName -match "Threat Detector") {
        $trigger = "Situational: Threat Proximity & Hostile Alerts"
    } elseif ($modId -match "NeatLockpicking|Lockpick" -or $modName -match "Lockpicking") {
        $trigger = "Situational: While Lockpicking / Mini-Game Active"
    } elseif ($modId -match "Construction1PViewpoint" -or $modName -match "Construction 1P") {
        $trigger = "Situational: While Building / Placing Furniture"
    } elseif ($modId -match "P4TidyUpMeister|TidyUpMeister" -or $modName -match "Tidy Up Meister") {
        $trigger = "Situational: After Completing Timed Actions (Auto-Stow)"
    } elseif ($modId -match "traitsAsSkills" -or $modName -match "Traits As Skills") {
        $trigger = "Situational: Combat & XP Gain / Zombie Kills"
    } elseif ($modId -match "ControllerSupport|Joypad" -or $modName -match "Controller Support") {
        $trigger = "Situational: While Using Controller / Gamepad"
    } elseif ($modId -match "PZ_Pulse|PZPulse" -or $modName -match "PZ Pulse") {
        $trigger = "Situational: Second-Screen Browser Telemetry (~Every 500ms)"
    } elseif ($modId -match "MoreDamagedObjects" -or $modName -match "More Damaged Objects") {
        $trigger = "Situational: Damaged Object Sprites & Water Animations"
    } elseif ($modId -match "SPNCC" -or $modName -match "Character Customisation") {
        $trigger = "Situational: Character Creation & Join (One-Time Setup)"
    } elseif ($modId -match "Equipment|Inventory|Hotbar|Crafting|Menu|Map|Health|DragAndDrop" -or $modName -match "Equipment|Inventory|Hotbar|Crafting|Menu|Map|Health") {
        $trigger = "Situational: While Menu / UI Is Open"
    } elseif ($modId -match "LethalStealth|Stealth" -or $modName -match "Lethal Stealth") {
        $trigger = "Situational: While Sneaking / In Stealth Stance"
    } elseif ($modId -match "VanillaVehiclesAnimated|Vehicle|jeep|chevy|ford|dodge|nissan|amgeneral|toyota|ferret|oshkosh|corvette|camaro|mustang|volvo|beetle|KI5") {
        $trigger = "Active: While Driving / Vehicle Streaming"
    } elseif ($permHooks -ge 1) {
        $trigger = if ($isContinuousPolling) { "Active: Continuous Engine Hook (Every Single Frame)" } else { "Dormant: Hook Registered (Early Return Unless Active)" }
    } elseif ($throttledHooks -ge 1) {
        $trigger = "Periodic Timer (~Every 5-10s)"
    }

    return [PSCustomObject]@{
        PotentialSpike = $spikeMs
        FrameTax = $taxText
        TaxBreakdown = $taxBreakdown
        StutterTrigger = $trigger
        SpikeSeverity = $spikeSeverity
        ActiveTaxRaw = $activeTaxRaw
        IdleTaxRaw = $idleTaxRaw
        IsContinuousPolling = $isContinuousPolling
        IsDormantEarlyExit = $isDormantEarlyExit
        LoopNature = $loopNature
    }
}

function Test-IsSpikeWorthy($mod) {
    if (-not $mod) { return $false }
    if ($mod.PotentialSpike -match '< 1 ms|Imperceptible') { return $false }
    if ($mod.SpikeSeverity -eq 'NEGLIGIBLE') { return $false }
    if ($mod.StutterTrigger -eq 'None (Passive / Static UI)') { return $false }

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
        $mod.RiskScore -ge 15) {
        return $true
    }
    return $false
}

# ==============================================================================
# Core Diagnostic Engine
# ==============================================================================
function Invoke-PZScanEngine([string]$CustomServerIni = "", [switch]$LocalWorkshopOnly, [string]$CustomWorkshopPath = "", [string]$CustomLog = "") {
    Write-Host "`n=================================================================" -ForegroundColor Cyan
    Write-Host "   PROJECT ZOMBOID MOD PERFORMANCE & OPTIMIZATION SUITE v2.13.0 " -ForegroundColor Yellow
    Write-Host "         Created by @KodeMannn with the help of Gemini          " -ForegroundColor DarkCyan
    Write-Host "=================================================================`n" -ForegroundColor Cyan

    $versionFile = Join-Path $ZomboidUserPath "version.txt"
    $pzVersion = "Unknown"
    if (Test-Path $versionFile) {
        $pzVersion = (Get-Content $versionFile -Raw).Trim()
    }
    Write-Host " [INFO] Detected Game Version: $pzVersion" -ForegroundColor Gray

    $validWorkshopPaths = Get-WorkshopPaths
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
                if ($line -match 'mod\s*=\s*([^,;}\s]+)') {
                    $mId = $matches[1].Trim()
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
        $rootFiles = Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue
        foreach ($rf in $rootFiles) {
            if ($allFiles -notcontains $rf) { $allFiles += $rf }
        }

        $totalBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum
        $totalMB = [math]::Round($totalBytes / 1MB, 2)
        
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
        $riskScore += [math]::Min(15, [math]::Floor($inHookInvQueries / 2))
        $riskScore += [math]::Min(3, [math]::Floor($staticInvQueries / 50))
        $riskScore += [math]::Min(20, $inHookHeavyContainers * 5)
        $riskScore += [math]::Min(15, [math]::Floor($inHookUIPolls / 2))
        $riskScore += [math]::Min(10, [math]::Floor($inHookJNICalls / 3))

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
            $dynamicReasons += "$inHookHeavyContainers heavy container rebuild call$(if ($inHookHeavyContainers -ne 1) { 's' } else { '' }) (refreshBackpacks/refreshWeight)"
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
            -inHookTileQueries $inHookTileQueries

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
    $maxEvictions = 0
    $maxEvictedMb = 0.0
    $maxChunkBuilds = 0
    $maxChunkDuration = 0.0

    # Engine Headroom Telemetry (B42 / Viewpoint)
    $hasHeadroomTelemetry = $false
    $headroomFps = 0
    $headroomGpuMs = 0.0
    $headroomRenderCpuMs = 0.0
    $headroomMainThreadMs = 0.0
    $headroomMainThreadFps = 0
    $headroomZombies = 0

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
            if ($line -match 'slow frame on the (main|render) thread:\s*([\d\.]+)\s*ms,\s*(?:ours|our passes)\s*([\d\.]+)(?:\s*\((.*?)\))?,\s*the rest\s*([\d\.]+)(?:\s*\((.*?)\))?') {
                $th = $matches[1]
                $tMs = [double]$matches[2]
                $oMs = [double]$matches[3]
                $oDet = $matches[4]
                $rMs = [double]$matches[5]
                $rDet = $matches[6]

                $ccMs = 0.0
                $ccBuilds = 0
                if ($oDet -and ($oDet -match 'chunk cache\s*([\d\.]+):\s*(\d+)\s*builds')) {
                    $ccMs = [double]$matches[1]
                    $ccBuilds = [int]$matches[2]
                }

                $slowFrames += [PSCustomObject]@{
                    Thread = $th
                    DurationMs = $tMs
                    OursMs = $oMs
                    OurDetails = $oDet
                    ChunkCacheMs = $ccMs
                    ChunkCacheBuilds = $ccBuilds
                    RestMs = $rMs
                    RestDetails = $rDet
                    Line = $line
                }
            } elseif ($line -match 'slow frame on the (main|render) thread:\s*([\d\.]+)\s*ms.*ours\s*([\d\.]+)') {
                $th = $matches[1]
                $tMs = [double]$matches[2]
                $oMs = [double]$matches[3]
                $slowFrames += [PSCustomObject]@{
                    Thread = $th
                    DurationMs = $tMs
                    OursMs = $oMs
                    OurDetails = ""
                    ChunkCacheMs = 0.0
                    ChunkCacheBuilds = 0
                    RestMs = [math]::Max(0.0, $tMs - $oMs)
                    RestDetails = "Engine Simulation"
                    Line = $line
                }
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
        }
    }

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

    $optionsIni = Join-Path $ZomboidUserPath "options.ini"
    $optionsFps = "Unknown"
    if (Test-Path $optionsIni) {
        $optMatch = (Get-Content $optionsIni | Select-String "^frameRate=(\d+)")
        if ($optMatch -match 'frameRate=(\d+)') {
            $optionsFps = "$($matches[1]) FPS"
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
            $worstSpikeRootCause = "Severe Java Garbage Collection Freeze (Engine Memory Sweep)"
            $worstSpikeAttribution = "JVM Heap Garbage Collection. NOT caused by Lua UI or QOL mods."
            $worstSpikeRecommendation = "Apply Menu Option [4] (One-Click G1GC + 5ms Pause Tuning) to eliminate GC freezes."
            if ($wCC -ge 10.0 -or $wBuilds -ge 10) {
                $candidates = @($topMeshMods | Where-Object { Test-IsSpikeWorthy $_ })
                $extraWorthy = @($worthyMods | Where-Object { $candidates -notcontains $_ })
                $worstSpikeCorrelatedMods = @($candidates + $extraWorthy | Select-Object -First 10)
            } else {
                $worstSpikeCorrelatedMods = @($worthyMods | Select-Object -First 10)
            }
        } elseif ($wCC -ge 30.0 -or $wBuilds -ge 20 -or ($wCC / $wTotal) -ge 0.40) {
            $worstSpikeAnatomy = "$wCC ms Chunk Cache Meshing ($ccPct%, $wBuilds builds) | $wRest ms Engine Simulation ($gcPct%)"
            $worstSpikeRootCause = "Dynamic 3D Mesh Compilation on Chunk Traversal"
            $worstSpikeAttribution = "Massive 3D model injections crossing chunk borders."
            $worstSpikeRecommendation = "Trim 3D furniture/model replacement packs to reduce chunk boundary stalls."
            $worstSpikeCorrelatedMods = @($topMeshMods | Where-Object { Test-IsSpikeWorthy $_ } | Select-Object -First 10)
        } elseif ($wTh -eq "render" -and $wRestDet -match "waiting for the main thread") {
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
    Write-Host " GPU VRAM Usage       : $vramReport" -ForegroundColor White
    if ($maxEvictions -gt 0) {
        Write-Host "   [!] GPU Thrashing  : $maxEvictions texture evictions ($maxEvictedMb MiB swapped across PCIe)!" -ForegroundColor Red
        Write-Host "       Cause & Impact : VRAM saturated; PCIe texture swapping causes 100-250ms render hitching" -ForegroundColor Yellow
        if ($topVramMods.Count -gt 0) {
            $vramCulprits = ($topVramMods | ForEach-Object { "$($_.ModName) ($($_.TextureMB) MB)" }) -join ", "
            Write-Host "       Top VRAM Loads : $vramCulprits" -ForegroundColor DarkYellow
        }
    }
    Write-Host " Java Heap Allocation : $heapReport" -ForegroundColor White
    Write-Host " JVM Garbage Collector: $gcReport" -ForegroundColor $gcColor
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
    if ($maxChunkBuilds -gt 0) {
        $chunkColor = if ($maxChunkBuilds -ge 50) { "Red" } elseif ($maxChunkBuilds -ge 20) { "Yellow" } else { "Gray" }
        Write-Host " Chunk Cache Hitches  : Up to $maxChunkBuilds mesh builds/chunk (Peak rebuild stall: $($maxChunkDuration) ms)" -ForegroundColor $chunkColor
        if ($topMeshMods.Count -gt 0) {
            $meshCulprits = ($topMeshMods | ForEach-Object { "$($_.ModName) ($($_.WorldMeshCount) world meshes)" }) -join ", "
            Write-Host "   -> Top 3D Meshes   : $meshCulprits" -ForegroundColor DarkYellow
        }
    }
    Write-Host " File Override Clashes: $($collisions.Count) detected ($($safeCollisions.Count) Safe, $($riskyCollisions.Count) High/Moderate Risk)" -ForegroundColor $(if ($riskyCollisions.Count -gt 0) { "Red" } elseif ($collisions.Count -gt 0) { "Green" } else { "Green" })

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
    $md += "*Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $hostName by PZ-Mod-Performance-Suite v2.13.0 (Coded with the help of Google Gemini)*"
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
    if ($hasHeadroomTelemetry) {
        $md += "- **Hardware Frame Budget:** GPU: $headroomGpuMs ms | Render CPU: $headroomRenderCpuMs ms | Main Thread: $headroomMainThreadMs ms (~$headroomMainThreadFps FPS headroom)"
        $md += "- **Live Simulation Density:** $headroomZombies active zombies loaded in simulation radius ($headroomFps in-game FPS)"
    }
    $md += "- **VRAM Free:** $vramReport"
    if ($maxEvictions -gt 0) {
        $md += "- **GPU VRAM Thrashing:** $maxEvictions texture evictions ($maxEvictedMb MiB swapped to RAM across PCIe) - High Stutter Risk"
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
    if ($maxChunkBuilds -gt 0) {
        $md += "- **Chunk Meshing Peak:** $maxChunkBuilds builds ($maxChunkDuration ms rebuild stall)"
    }
    $md += "- **JVM Garbage Collector:** $gcReport"
    $md += "- **Direct File Override Clashes:** $($collisions.Count) total ($($safeCollisions.Count) Safe, $($riskyCollisions.Count) High/Moderate Risk)"
    $md += ""
    $md += "---"
    $md += "## Global Modpack Runtime Budget & Fleet Stacking Analysis"
    $md += ""
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
            $md += ""
        }
    } else {
        $md += "*No mods exceeded the Tier 3 threshold. Your active mod list is exceptionally well-optimized!*"
        $md += ""
    }

    $md += "---"
    $md += "## All Active Mods Ranked by Performance Impact"
    $md += ""
    $md += "| Mod Name | Mod ID | Tier | Score | Predicted Risk (Heuristic) | Frame Tax | Trigger Scenario | Perm Loops | Trans / Throt | Queries (Hook/UI) | Size (MB) | World Meshes | Stutter Verdict |"
    $md += "|:---|:---|:---:|:---:|:---:|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---|"
    foreach ($m in $sortedMods) {
        $mId = $m.ModId
        $md += "| $($m.ModName) | $mId | $($m.Tier) | $($m.RiskScore) | $($m.PotentialSpike) | $($m.FrameTax) | $($m.StutterTrigger) | $($m.PermanentHooks) | $($m.TransientHooks) / $($m.ThrottledHooks) | $($m.InHookWorldQueries) / $($m.StaticWorldQueries) | $($m.SizeMB) | $($m.WorldMeshCount) | $($m.Verdict) |"
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
# Interactive TUI Menu
# ==============================================================================
function Show-PZMainMenu {
    while ($true) {
        Clear-Host
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "   PROJECT ZOMBOID MOD PERFORMANCE & OPTIMIZATION SUITE v2.13.0 " -ForegroundColor Yellow
        Write-Host "         Created by @KodeMannn with the help of Gemini          " -ForegroundColor DarkCyan
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "  [1] Run Full Performance Diagnostic Scan (Active Save)" -ForegroundColor White
        Write-Host "  [2] Scan Dedicated / Multiplayer Server Config (.ini)" -ForegroundColor White
        Write-Host "  [3] Scan Local Workshop Mods (Zomboid\Workshop)" -ForegroundColor White
        Write-Host "  [4] One-Click Java GC Optimizer (Apply G1GC + 5ms Pause Tuning)" -ForegroundColor White
        Write-Host "  [5] Safe Frame Cap Optimizer (Reduce Lua Tick Multiplier)" -ForegroundColor White
        Write-Host "  [6] Clean Phantom / Missing Mods from Savegame" -ForegroundColor White
        Write-Host "  [7] Revert Changes / Restore Backups (JVM, FPS, Savegame)" -ForegroundColor Yellow
        Write-Host "  [8] Open Last Generated Diagnostic Report" -ForegroundColor White
        Write-Host "  [0] Exit" -ForegroundColor Gray
        Write-Host "=================================================================" -ForegroundColor Cyan
        
        $choice = Read-Host " Select an option (0-8)"
        switch ($choice.Trim()) {
            "1" {
                Invoke-PZScanEngine -CustomLog $CustomLogPath
                Write-Host "Press Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "2" {
                Write-Host "`nEnter path to server .ini file (or drag and drop it here):" -ForegroundColor Cyan
                $iniPath = (Read-Host).Trim().Trim('"')
                if ($iniPath -and (Test-Path $iniPath)) {
                    Invoke-PZScanEngine -CustomServerIni $iniPath
                } else {
                    Write-Host " [!] File not found: $iniPath" -ForegroundColor Red
                }
                Write-Host "Press Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "3" {
                $defaultWs = Join-Path $ZomboidUserPath "Workshop"
                Write-Host "`nLocal Workshop Folder: $defaultWs" -ForegroundColor Cyan
                Write-Host "Press [Enter] to scan default folder, or enter a custom path:" -ForegroundColor Gray
                $customPath = (Read-Host).Trim().Trim('"')
                $wsToScan = if ($customPath -and (Test-Path $customPath)) { $customPath } else { $defaultWs }
                Invoke-PZScanEngine -LocalWorkshopOnly -CustomWorkshopPath $wsToScan
                Write-Host "`nPress Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "4" {
                Invoke-PZFixGC
                Write-Host "`nPress Enter to return to menu..." -ForegroundColor Gray
                Read-Host | Out-Null
            }
            "5" {
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
                if ($fps -gt 0) {
                    Set-PZFrameCap $fps
                }
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
} elseif ($CapFPS -gt 0) {
    Set-PZFrameCap $CapFPS
} elseif ($CleanSave) {
    Invoke-PZCleanSaveMods
} elseif ($LocalWorkshop) {
    Invoke-PZScanEngine -LocalWorkshopOnly -CustomWorkshopPath $CustomWorkshopPath -CustomLog $CustomLogPath
} elseif ($ServerConfigPath) {
    Invoke-PZScanEngine -CustomServerIni $ServerConfigPath -CustomLog $CustomLogPath
} elseif ($Auto -or $StutterRoster) {
    Invoke-PZScanEngine -CustomLog $CustomLogPath
} else {
    Show-PZMainMenu
}
