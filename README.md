# PZ-Mod-Performance-Suite ⚡
**Advanced Mod Performance Diagnostic & Optimization Suite for Project Zomboid (Build 42 & 41)**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Discord](https://img.shields.io/badge/Discord-Join%20Community-5865F2?logo=discord&logoColor=white)](https://discord.gg/5rmsnwMPez)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)]()
[![Game](https://img.shields.io/badge/Project%20Zomboid-Build%2042%20%7C%2041-darkgreen.svg)](https://projectzomboid.com/)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero-brightgreen.svg)]()
[![AI Assisted](https://img.shields.io/badge/Coded%20with-Google%20Gemini-8E75C2?logo=google&logoColor=white)]()

**PZ-Mod-Performance-Suite** is a fast, standalone diagnostic scanner and 1-click optimization toolkit engineered to identify and eliminate micro-stutters, FPS hitching, Lua frame budget overflows, and Java garbage collection freezes in Project Zomboid.

Whether you're running a heavily modded singleplayer save or hosting a dedicated multiplayer server, **PZ-Mod-Performance-Suite** audits active mods across all your Steam libraries, classifies harmless localization merges from high-risk executable script conflicts, and applies verified low-latency engine tuning.

> ℹ️ **Disclaimer:** This project was designed and developed by [@KodeMannn](https://github.com/KodeMannn) with the coding assistance and pair-programming of **Google Gemini**.

---

## ⚡ Quick Start

### 🪟 Windows (One-Click Executable)
1. **Download**: Grab [`Scan-PZModPerformance.bat`](https://github.com/KodeMannn/PZ-Mod-Performance-Suite/releases/latest) (single-file, zero dependencies).
2. **Run**: Double-click `Scan-PZModPerformance.bat` anywhere on your computer (Desktop, your `Zomboid` folder, or server directory).
3. **Choose Option**: Use the interactive terminal menu to run a full diagnostic scan, apply 1-click JVM GC optimization, set safe frame caps, clean ghost mods, or revert changes.
4. **Play Smooth**: Review the color-coded report before surviving Kentucky with zero micro-stutters.

### 💻 PowerShell / CLI Power Users
Run interactive or automated scans with command-line flags:
```powershell
# Interactive menu:
.\Scan-PZModPerformance.ps1

# Non-interactive automatic scan:
.\Scan-PZModPerformance.ps1 -Auto

# Audit only the Stutter & Lag Spike Impact Roster:
.\Scan-PZModPerformance.ps1 -StutterRoster

# Audit a dedicated server config:
.\Scan-PZModPerformance.ps1 -ServerConfig "$env:USERPROFILE\Zomboid\Server\servertest.ini"

# Apply 1-click JVM garbage collection fix:
.\Scan-PZModPerformance.ps1 -FixGC

# Apply safe 120 FPS cap:
.\Scan-PZModPerformance.ps1 -CapFPS 120

# Clean ghost mods from current save:
.\Scan-PZModPerformance.ps1 -CleanSave

# Revert all changes and restore original backups:
.\Scan-PZModPerformance.ps1 -Revert All
```

> **Zero Dependencies:** Requires no installation, no extra modules, and no separate `.ps1` file. Runs out-of-the-box on Windows 10 & 11 via native PowerShell-Batch polyglot execution.

---

## 🚀 Suite Profiles & Operations

PZ-Mod-Performance-Suite features 8 selectable operations to fit your workflow:

| Profile | Action / Target | Typical Duration | Best For |
| :--- | :--- | :--- | :--- |
| **`[1] Full Diagnostic Scan`** *(Default)* | Active Save (`mods.txt`), Workshop, Lua Hooks, VRAM, Hitches, Stutter Roster, Overrides | **~2.5 seconds** | Complete performance, stutter ranking & conflict audit of active save |
| **`[2] Dedicated Server Scan`** | Dedicated server `.ini` files (`servertest.ini` or custom path) | **~2.5 seconds** | Auditing server modpacks for VPS, Pterodactyl, and Co-op hosts |
| **`[3] Scan Local Workshop Mods`** | Local workshop development folder (`Zomboid\Workshop`) | **< 1 second** | Profiling custom mods under development before publishing to Steam |
| **`[4] 1-Click Java GC Tuning`** | `ProjectZomboid64.json` launcher configuration | **< 1 second** | Eliminating 200–400ms periodic world freezes via low-latency G1GC |
| **`[5] Safe Frame Cap Tuning`** | `options.ini` display frameRate setting | **< 1 second** | Throttling Lua tick execution overhead down from 240/uncapped FPS |
| **`[6] Clean Phantom Mods`** | Active savegame `mods.txt` | **< 1 second** | Purging uninstalled ghost mods to stop console spam and speed up boot |
| **`[7] Revert Changes / Backups`** | JVM config, FPS cap, and savegame mods | **< 1 second** | Safely restoring original `.bak` backups and vanilla engine settings |
| **`[8] Open Last Report`** | `ModPerformanceReport.md` | **Instant** | Viewing detailed breakdown, conflict tables, and Discord summaries |

---

## 🔍 Key Features

* **⚡ Ultra-Fast Multi-Library Workshop Indexing:** Finds mods across all Steam drives (`C:`, `D:`, `E:`, `H:`, external NVMe SSDs) via `libraryfolders.vdf`.
* **📋 Full Stutter & Lag Spike Impact Roster (v2.6.0):** Clean, 1-line tabular roster displaying every active mod with predicted frame spike bounds, severity status, and exact gameplay trigger events. Replaces visual clutter with unified per-row severity colors (Red for Tier 1, Yellow for Tier 2, DarkYellow for Tier 3, DarkGray for Tier 4).
* **🎯 Expanded Top 5 Correlated Spike Culprits (v2.6.0):** Deeply correlates recorded engine slow frames across the top 5 contributing mods with actionable root cause attribution.
* **🩺 Precision Slow Frame Anatomy Dissection (v2.5.0):** Dissects every slow-frame log line in Build 42 into its component sub-stalls:
  * **Main vs. Render Thread Origin:** Distinguishes CPU simulation freezes from GPU draw stalls.
  * **Java GC Pauses vs. Chunk Meshing:** Measures the exact millisecond pause caused by JVM garbage collection sweeps (`the collector's pauses`) versus geometry compilation (`chunk cache builds`).
  * **Actionable Root Cause:** Pinpoints whether a spike requires JVM G1GC tuning (Option `[4]`) or custom 3D model trimming.
* **🛡️ Causal Bottleneck Filtering (Zero False Mod Accusations):** Prevents innocent Lua UI or QOL mods from being falsely blamed for world hitches. If an engine freeze is caused by Java GC sweeps or chunk meshing, the suite attributes the stall directly to JVM memory or 3D mesh packs, keeping QOL mod ratings clean and accurate.
* **⏱️ Hardware Frame Times & Simulation Headroom:** Extracts real-time GPU render times, Render CPU frame times, and Main Thread simulation duration (`main thread frame 9.70 ms -> 103 FPS headroom`) alongside active loaded zombie counts.
* **🔗 Multi-Culprit Telemetry Correlation Engine:** Deeply correlates recorded engine telemetry from `console.txt` across multiple bottleneck vectors:
  * **Frame Hitch Culprits:** Identifies and ranks the top 5 mods contributing to the worst recorded frame spike with predicted freeze durations and trigger events.
  * **GPU VRAM Thrashing Attributions:** Identifies the top 5 texture heavyweights responsible for saturated VRAM and PCIe bus paging freezes.
  * **Chunk Cache Hitching:** Surfacing the top 5 3D mesh injectors causing chunk rebuild stalls during world traversal.
  * **Continuous CPU Tick Drag:** Isolates the top 5 mods burning frame budget every single tick.
* **⏳ Seamless Multi-Phase Loading Bar:** Features an end-to-end 4-phase progress indicator (Mod Auditing $\rightarrow$ Collision Classification $\rightarrow$ Telemetry Parsing $\rightarrow$ Correlation Synthesis & Ranking) that keeps the console responsive with zero visual freeze before displaying results.
* **🌐 Global Modpack Runtime Budget & Loop Density Engine:** Solves the elusive "death by 1,000 cuts" where 50+ lightweight mods cumulatively overflow CPU frame budgets. Aggregates total persistent CPU tax (+ms/frame), counts active per-frame loops across the entire modpack, and fires High Loop Density alerts.
* **🏎️ Mass Vehicle Fleet Stacking Aggregator:** Flags when players accumulate 15+ vehicle mods running per-frame tachometer/speedometer loops (e.g. `DorothyAnemometer`), revealing cumulative frame tax (+6.75 ms/frame) and thousands of loaded vehicle meshes.
* **🎮 GPU VRAM Eviction & Texture Thrashing Detector:** Telemetry-based detector that parses Build 42 deferred renderer logs for texture evictions across the PCIe bus, identifying the root cause of 100–250ms render-thread freezes while running or driving.
* **🗺️ Chunk Cache Meshing Traversal Telemetry:** Monitors chunk boundary mesh builds and rebuild stalls, isolating stutter caused by massive 3D model injections when crossing world boundaries.
* **🔒 Safe Concurrent Log Streaming:** Uses non-locking `[System.IO.FileShare]::ReadWrite` streams to safely run scans and parse telemetry even while Project Zomboid is actively running.
* **⏱️ Static Code Risk Prediction Engine (v2.2.0):** Estimates concrete worst-case freeze durations based on structural code intensity and asset weight:
  * `~350-550 ms [Severe Freeze]`: Massive 3D model injections causing chunk meshing stalls.
  * `~100-250 ms [Noticeable Hitch]`: Heavy texture packs causing VRAM paging spikes.
  * `~50-150 ms [Action Spike]`: High-volume transient hooks triggered by player actions (e.g. transcribing XP).
  * `~10-35 ms [Combat Hitch]`: High-frequency world square / zombie entity scans during horde combat.
  * `< 1 ms [Imperceptible]`: Harmless UI, texture replacements, or benign passive mods.
* **📈 Continuous Frame Time Tax (+ms/frame):** Calculates exact persistent CPU cost added to every frame budget (e.g., `+1.38 ms/frame`).
* **🎯 Stutter Trigger Scenario Classification:** Identifies exact gameplay triggers causing lag (`Chunk Border Traversal & High-Speed Driving`, `Horde Proximity & Combat`, `Action: Transcribing / Reading XP`, `Vehicle Spawn & Streaming`, etc.).
* **🧠 Intelligent Semantic Lua Auditor:** Evaluates Lua code semantics to differentiate:
  * **Permanent Loops:** Unconstrained hooks executing every frame at 100–240 FPS (heavily penalized).
  * **Transient Hooks:** Self-terminating hooks with `.Remove` calls (UI listeners, 1-tick bootstrappers, retry loops) that cost virtually zero at runtime.
  * **Throttled / Gated Handlers:** Hooks gated by modulo counters (`% 30`), interval timers (`counter >= 500`), or idle state returns (`if n == 0 return`).
* **📁 Build 42 Version-Aware Deduplication:** Accurately targets the active version subfolder (e.g. `42.20` or `42.14` + `common/`), eliminating 2x–3x score inflation from historical version directories.
* **🎯 In-Hook Query Separation:** Distinguishes high-frequency per-frame world queries (`getZombieList`, `getSquare`) from harmless interactive queries executed only when clicking context menus or crafting.
* **🛠️ Local Workshop Staging Audit:** Directly scans custom mods being authored in your local `Zomboid\Workshop` folder without needing an active save.
* **🎨 Texture & VRAM Bloat Measurement:** Measures `.pack` texture archives and raw `.png` footprints, warning when mods consume excessive graphics memory (>100MB).
* **🛡️ Intelligent Conflict & Override Classifier:** Automatically classifies mod file overlaps into:
  * **Safe (Translations & Shared UI):** Verifies harmless localization dictionary merges (`/translate/`), shared category icons, and Git metadata.
  * **High Risk (Executable Lua Overrides):** Isolates direct Lua code replacements (`client/`, `server/`, `shared/`) that can break gameplay mechanics or cause multiplayer desyncs.
* **👻 Ghost Mod Filtering:** Automatically skips uninstalled mods from the performance audit so phantom references in `mods.txt` don't distort risk scores.
* **⚙️ 1-Click JVM Garbage Collection Tuning:** Patches `ProjectZomboid64.json` to low-latency G1GC (`-XX:MaxGCPauseMillis=5`, `-Dpzopt.gc=g1`, `-Xmx16g`) with automatic `.bak` backup to eliminate 200–400ms complete freezes.
* **🎯 Safe Frame Rate Limiter:** Easily switches `frameRate` in `options.ini` between 60, 120, 144, or custom FPS to avoid running tick hooks 240 times/sec.
* **🧹 Savegame Ghost Mod Cleaner:** Automatically discovers and removes deleted mods from active save files (`mods.txt`).
* **🔄 Full Rollback & Revert Engine:** Restore any optimization back to original vanilla defaults with a single keypress.
* **📝 Markdown & Discord Export:** Generates rich markdown reports and a copy-pasteable summary block for Discord/Reddit community troubleshooting.

---

## 🛡️ Bottleneck Detection & Risk Matrix

| Bottleneck Category | Engine Impact | Severity | Primary Culprits |
| :--- | :--- | :--- | :--- |
| **VRAM & Chunk Meshing Choke** | Stalls render thread for 350–550ms when moving across chunk boundaries | **CRITICAL** | Massive 3D model injection packs (10,000+ models, >150MB textures) |
| **GPU VRAM Thrashing & PCIe Swapping** | Causes 100–250ms render-thread freezes when VRAM fills and textures swap to RAM | **CRITICAL** | Heavy texture packs combined with dozens of vehicle mods (>12GB VRAM) |
| **Cumulative Modpack Loop Density** | "Death by 1,000 cuts": 15–80+ background loops consume main-thread CPU budget | **CRITICAL** | Stacking 50–80+ vehicle mods each running per-frame `DorothyAnemometer` |
| **Unconstrained Permanent Lua Loops** | Consumes main-thread CPU budget running Lua calculations 240 times/sec | **CRITICAL** | Heavy `OnTick`, `OnPlayerUpdate` loops without throttle guards |
| **Java GC Memory Sweeps** | Freezes entire world for 200–400ms during garbage collection | **HIGH RISK** | Oversized heap (`-Xmx32g`), ZGC pauses under Lua table churn |
| **Missing Asset / Error Floods** | Floods `console.txt` with template syntax & missing asset disk logging | **HIGH RISK** | Outdated vehicle or animation templates in Build 42 |
| **Direct Lua Script Collisions** | One mod silently overrides another mod's script logic | **HIGH RISK** | Overlapping files in `media/lua/client/` or `server/` |
| **Per-Frame World Entity Queries** | High CPU cost continuously scanning zombies/squares in radius inside tick loops | **MODERATE** | In-hook `getZombieList()`, `getSquare()` loops |
| **Throttled / Periodic Handlers** | Minimal CPU cost executing only once every 30–500 ticks | **SAFE / LOW** | Modulo tick counters (`%`), timer accumulators, idle guards |
| **Transient Hooks & Bootstrappers** | Fires for 1 frame on boot or UI open, then calls `Events.*.Remove` | **SAFE** | 1-tick monkey-patches, UI listeners, action callbacks |
| **Localization & Icon Merges** | Standard dictionary merge; no gameplay logic altered | **SAFE** | Translation files (`/translate/`), shared category icons |

---

## 📊 Sample Output

```text

=================================================================
   PROJECT ZOMBOID MOD PERFORMANCE & OPTIMIZATION SUITE v2.6.1  
         Created by @KodeMannn with the help of Gemini          
=================================================================

 [INFO] Detected Game Version: 42.21.0
 [INFO] Active Savegame: Outbreak / 2026-10-04_16-33-03
 [INFO] Total Enabled Mods to Audit: 56

-----------------------------------------------------------------
   RUNTIME ENGINE TELEMETRY SUMMARY
-----------------------------------------------------------------
 Configured Frame Cap : 240 FPS (Active: 240 FPS)
 GPU VRAM Usage       : 2381 MB free of 12282 MB
   [!] GPU Thrashing  : 2 texture evictions (32 MiB swapped across PCIe)!
       Top VRAM Loads : 6261 3D models for Viewpoint (170.79 MB), KATTAJ1 Military Pack (54.06 MB)
 Java Heap Allocation : 2736 MB used of 6992 MB
 JVM Garbage Collector: 0 Old Gen Freezes | Young Gen: 99 sweeps (avg 7.1 ms, 700 ms total)
 Slow Frames (>50ms)  : 19 recorded in last session
 Worst Frame Spike    : 446.4 ms (MAIN THREAD)
   -> SPIKE ANATOMY   : 425.1 ms Engine & GC Pauses (95.2%) | 21.3 ms Chunk Meshing & Passes (4.8%)
   -> ROOT CAUSE      : Severe Java Garbage Collection Freeze (Engine Memory Sweep)
   -> ATTRIBUTION     : JVM Heap Garbage Collection. NOT caused by Lua UI or QOL mods.
   -> ACTIONABLE FIX  : Apply Menu Option [4] (One-Click G1GC + 5ms Pause Tuning) to eliminate GC freezes.
   -> TOP CORRELATED SPIKE CULPRITS:
      [1] 6261 3D models for Viewpoint ... | Pred: ~350-550 ms [Severe Freeze]  | Chunk Border Traversal & High-Speed Driving
      [2] Project Viewpoint QOL            | Pred: ~10-35 ms [Combat Hitch]     | Horde Proximity & Combat
      [3] Functional Appliances 2          | Pred: ~10-35 ms [Combat Hitch]     | Horde Proximity & Combat
      [4] ZombieBuddy                      | Pred: ~10-35 ms [Combat Hitch]     | Horde Proximity & Combat
      [5] NeatUI XP Drop                   | Pred: ~2-8 ms [Frame Delay]        | Continuous (Every Single Frame)
 Chunk Cache Hitches  : Up to 40 mesh builds/chunk (Peak rebuild stall: 100.1 ms)
   -> Top 3D Meshes   : 6261 3D models for Viewpoint [sour_kisel] (10241 meshes), Fluffy Hair (163 meshes)
 File Override Clashes: 433 detected (431 Safe, 2 High/Moderate Risk)

-----------------------------------------------------------------
   GLOBAL MODPACK RUNTIME BUDGET & LOOP DENSITY
-----------------------------------------------------------------
 Cumulative Mod Frame Tax : +2.58 ms/frame (Continuous CPU tick overhead)
 Active Per-Frame Loops   : 2 permanent hooks firing every single frame
 Total Custom 3D Models   : 10512 meshes (285.77 MB textures across mods)
   -> Top CPU Tick Tax: NeatUI XP Drop (+0.45 ms/frame), NeatUI Equipment (+0.45 ms/frame), Project Viewpoint QOL (+0.76 ms/frame)

-----------------------------------------------------------------
   ACTIVE MODS RANKED BY STUTTER & LAG SPIKE POTENTIAL
   (Worst-case burst prediction & trigger scenario across all active mods)
-----------------------------------------------------------------
  Rank Mod Name                         | Spike Potential (Predicted Burst)  | Trigger Scenario
 ----- -------------------------------- | ---------------------------------- | -----------------------------------
 [01]  6261 3D models for Viewpoint ... | Pred: ~350-550 ms [Severe Freeze]  | Chunk Border Traversal & High-Speed Driving
 [02]  Project Viewpoint QOL            | Pred: ~10-35 ms [Combat Hitch]     | Horde Proximity & Combat
 [03]  Functional Appliances 2          | Pred: ~10-35 ms [Combat Hitch]     | Horde Proximity & Combat
 [04]  NeatUI XP Drop                   | Pred: ~2-8 ms [Frame Delay]        | Continuous (Every Single Frame)
 [05]  NeatUI Equipment                 | Pred: ~2-8 ms [Frame Delay]        | Continuous (Every Single Frame)
 [06]  Push Vehicle                     | Pred: ~5-15 ms [Minor Blip]        | Vehicle Spawn & Streaming
 [07]  Fluffy Hair                      | Pred: < 1 ms [Imperceptible]       | None (Passive / Static UI)
 [08]  Realistic Dashboard and Gauges   | Pred: ~5-15 ms [Minor Blip]        | Periodic Timer (~Every 5-10s)
 ...
```

---

## 🛠️ General Optimization Recommendations for Build 42

1. **Cap Your Frame Rate:**
   If your display is 60Hz or 144Hz, do not leave your frame rate uncapped or set to 240 FPS in Project Zomboid's display settings. Setting a cap of 120 or 144 FPS instantly cuts Lua tick overhead by up to 50%.
2. **Tame Massive 3D Model Packs:**
   If your GPU has 8GB–12GB of VRAM and you experience 100–250ms hitches when driving into town or entering buildings, disable custom 3D voxel furniture packs while keeping your core camera/lighting mods.
3. **JVM Garbage Collection Tuning:**
   If you experience 200–400ms complete world freezes every minute or two, use Menu Option `[3]` or open `ProjectZomboid64.json` in your game install folder:
   - Reduce `-Xmx32g` to `-Xmx16g`.
   - Under `"windows" -> "10.0.17134"`, replace `-XX:+UseZGC` with `-XX:+UseG1GC`, `-Dpzopt.gc=g1`, and `-XX:MaxGCPauseMillis=5`.

---

## 💬 Community & Discord

Have questions, feedback, or want to discuss Project Zomboid modding performance and optimization?
Join our community on Discord:

👉 **[Join our Discord Server](https://discord.gg/5rmsnwMPez)**

---

## 🤝 Contributing & Support

If you encounter an issue, have a false positive risk flag, or want to suggest an optimization:
1. Open an issue on GitHub at [Issues](https://github.com/KodeMannn/PZ-Mod-Performance-Suite/issues).
2. Reach out on [Discord](https://discord.gg/5rmsnwMPez).

Pull requests to improve detection heuristics, expand optimization profiles, or add features are always welcome!

---

## 📄 License

Distributed under the [MIT License](LICENSE). Copyright (c) 2026 KodeMannn.
