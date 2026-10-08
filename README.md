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

### 🪟 Windows (One-Click Standalone Executable)
1. **Download**: Grab [**`Scan-PZModPerformance.bat`**](https://github.com/KodeMannn/PZ-Mod-Performance-Suite/releases/latest/download/Scan-PZModPerformance.bat) directly (single-file standalone executable — zero dependencies, zero zip extraction required).
2. **Run**: Double-click `Scan-PZModPerformance.bat` anywhere on your computer (Desktop, your `Zomboid` folder, or server directory).
3. **Choose Option**: Use the interactive terminal menu to run a full diagnostic scan, apply 1-click JVM GC optimization, set safe frame caps, clean ghost mods, or revert changes.
4. **Play Smooth**: Review the color-coded report before surviving Kentucky with zero micro-stutters.

### 🐧 Linux & 🍎 macOS (including Steam Deck / SteamOS)
1. **Download**: Grab [**`Scan-PZModPerformance.sh`**](https://github.com/KodeMannn/PZ-Mod-Performance-Suite/releases/latest/download/Scan-PZModPerformance.sh) and [**`Scan-PZModPerformance.ps1`**](https://github.com/KodeMannn/PZ-Mod-Performance-Suite/releases/latest/download/Scan-PZModPerformance.ps1) directly into the same folder (direct downloads — no zip archive required).
2. **Make Executable & Run**:
   ```bash
   chmod +x Scan-PZModPerformance.sh
   ./Scan-PZModPerformance.sh
   ```
3. **Steam Deck Ready (Zero-Root / Zero-Sudo)**:
   - If PowerShell Core (`pwsh`) is not yet installed on your system, `Scan-PZModPerformance.sh` automatically offers a **1-click portable download** directly into user-space (`~/.local/share/powershell`).
   - Requires **no root password**, works on Steam Deck's read-only SteamOS filesystem, and runs out-of-the-box!
   - Supports native package managers as well: `brew install --cask powershell` (macOS), `sudo apt install powershell` (Ubuntu/Debian), or `yay -S powershell-bin` (Arch).

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

# Ingest a specific engine log (e.g. Build 42 DebugLog or dedicated server log):
.\Scan-PZModPerformance.ps1 -CustomLogPath "$env:USERPROFILE\Zomboid\Logs\2026-10-05_09-02_DebugLog.txt"

# Specify a custom Steam Workshop or mod folder path (e.g. secondary drive D:\SteamLibrary):
.\Scan-PZModPerformance.ps1 -CustomWorkshopPath "D:\SteamLibrary\steamapps\workshop\content\108600"
```

> **Zero Dependencies:** Requires no installation, no extra modules, and no separate `.ps1` file. Runs out-of-the-box on Windows 10 & 11 via native PowerShell-Batch polyglot execution.

---

## 🚀 Suite Profiles & Operations

PZ-Mod-Performance-Suite features 9 selectable operations to fit your workflow:

| Profile | Action / Target | Typical Duration | Best For |
| :--- | :--- | :--- | :--- |
| **`[1] Full Diagnostic Scan`** *(Default)* | Active Save (`mods.txt`), Workshop, Lua Hooks, VRAM, Hitches, Stutter Roster, Overrides | **~2.5 seconds** | Complete performance, stutter ranking & conflict audit of active save |
| **`[2] Dedicated Server Scan`** | Dedicated server `.ini` files (`servertest.ini` or custom path) | **~2.5 seconds** | Auditing server modpacks for VPS, Pterodactyl, and Co-op hosts |
| **`[3] Scan Local Workshop Mods`** | Local workshop development folder (`Zomboid\Workshop` or custom) | **< 1 second** | Profiling custom mods under development before publishing to Steam |
| **`[4] 1-Click Java GC Tuning`** | `ProjectZomboid64.json` launcher configuration | **< 1 second** | Eliminating 200–400ms periodic world freezes via low-latency G1GC |
| **`[5] Safe Frame Cap Tuning`** | `options.ini` display frameRate setting | **< 1 second** | Throttling Lua tick execution overhead down from 240/uncapped FPS |
| **`[6] Clean Phantom Mods`** | Active savegame `mods.txt` | **< 1 second** | Purging uninstalled ghost mods to stop console spam and speed up boot |
| **`[7] Revert Changes / Backups`** | JVM config, FPS cap, and savegame mods | **< 1 second** | Safely restoring original `.bak` backups and vanilla engine settings |
| **`[8] Open Last Report`** | `ModPerformanceReport.md` | **Instant** | Viewing detailed breakdown, conflict tables, and Discord summaries |
| **`[9] Configure Workshop Path`** | Persistent config (`pz_scanner_config.json`) | **Instant** | Configuring custom Workshop or Steam library paths on secondary drives |

---

## 🔍 Key Features

* **💾 Multi-Drive Steam Library Discovery & Custom Workshop Paths (v2.17.0):**
  * **Dynamic Multi-Drive Enumeration:** Completely resolves workshop detection issues on secondary drives (e.g. `D:`, `E:`, `F:`, `G:`) and custom Steam library configurations. Automatically inspects Windows Registry (`Steam App 108600` uninstall key and Valve Steam install keys), iterates all active logical drives via `[System.IO.DriveInfo]::GetDrives()`, and parses `libraryfolders.vdf` across all drives with support for both modern and legacy VDF formatting.
  * **Persistent Custom Workshop Path Configuration (`pz_scanner_config.json`):** Provides Menu Option `[9]` to inspect discovered libraries and configure/persist a custom Steam Workshop or mod directory path without having to re-enter it on every run.
  * **Active Save Integration & Phantom Mod Protection:** Connects custom workshop paths into active save audits (Option `[1]`) and phantom mod cleanup (Option `[6]`), ensuring mods installed on secondary drives are properly profiled and never falsely flagged as missing.
  * **Interactive Fallback Prompt:** If auto-discovery finds 0 workshop paths during an active scan, the scanner interactively prompts the user to enter or drag-and-drop their Steam library folder on the spot rather than silently failing to local mods.
* **🎯 Multi-Scenario Trigger Taxonomy & Granular Performance Impact Matrix (v2.16.0):**
  * **Exhaustive Multi-Trigger Detection:** Completely eliminates the single-branch limitation where multi-faceted mods could only display one trigger scenario. Every active mod is now deeply evaluated across 8 operational dimensions (3D geometry compilation, VRAM texture streaming, continuous per-frame tick loops, state-gated interaction triggers, container rebuilds, vehicle physics & script checks, Java bytecode transforms, and dormant baselines).
  * **Granular Performance Impact for Every Scenario:** Quantifies predicted frame spikes, render stalls, and CPU frame taxes for each individual trigger scenario. For example, `Viewpoint (Core)` exposes all 4 operational states: Character & Skeletal Bone Snapshots (`~126-295 ms [Snapshot CPU Stall]`), Dynamic Lamp & Headlight Shadows (`~78-195 ms [Shadow Render Stall]`), 1P Camera Matrix Pass (`~10-25 ms [1P Render Pass] (+0.75 ms/frame)`), and Third-Person Mode Baseline (`< 1 ms [Imperceptible] (+0.15 ms/frame idle)`).
  * **Console TUI Multi-Row Hierarchy:** Renders the primary worst-case scenario on the main ranking row, while displaying cleanly indented sub-rows (`+-> Scenario N : [Name] | Impact: [Impact] | [Condition]`) directly underneath with pixel-perfect column alignment.
  * **Dedicated Report Impact Matrices:** Generates a structured **Operational Trigger Scenarios & Performance Impact Matrix** table for each Tier 1–3 mod in `ModPerformanceReport.md`, detailing scenario titles, predicted impacts, severity ratings, execution states, and activation conditions.
* **🔬 Next-Gen Deep Performance Telemetry & Engine Diagnostic Suite (v2.15.0):**
  * **Pillar 1: 3D Frustum & Geometry Telemetry (Render Thread Load):** Ingests live OpenGL/DirectX geometry stream from Build 42 / Viewpoint / RVV. Tracks peak draw calls per frame (flagging `CRITICAL` when draw calls exceed ~1,500/frame CPU driver dispatch ceiling), active 3D model instances, skeletal bone palette matrices (up to 18,600+ bones), shell blocks in view (up to 7.5M vertices held), committed system RAM (19+ GB), and live GPU VRAM saturation percentages (detecting ~10 GB VRAM saturation on 12 GB GPUs).
  * **Pillar 2: Consecutive Freeze Cluster Analysis (Multi-Frame Chains):** Detects sequential multi-frame stall chains that turn momentary hitches into catastrophic game freezes. Groups adjacent slow frames into clusters, computing composite freeze duration (e.g. `Frames 577–580: 1,370.7 ms total freeze across 5 frames`) and exposing the compound cascade where chunk cache boundary meshing and character snapshot bursts immediately trigger an unmitigated Java Garbage Collection sweep. Isolates Viewpoint internal shader spikes (lamp shadows up to 78.2 ms, G-buffer geometry up to 226.6 ms).
  * **Pillar 3: Engine Graphics Configuration Bottleneck Audit (`options.ini`):** Deeply audits in-game settings to identify options that multiply mod lag. Detects disabled texture compression (`textureCompression=false`, loading 4K clothing/vehicle textures uncompressed and consuming 10 GB VRAM), disabled 3D model mipmaps (`modelTextureMipmaps=false`, thrashing GPU cache lines and causing distance shimmering and frame pacing judder), and asynchronous tick rate dissonance (scene rendering at 120 FPS, UI rendering at 60 FPS, dynamic lighting ticking at 30 FPS without VSync).
  * **Pillar 4: JVM Bytecode Patch & Hook Registry (`[ZB]`):** Catalogs every native Java engine method intercepted at runtime by `ZombieBuddy` and `Viewpoint` across `console.txt` and `DebugLog.txt` (over 480 advice hooks across 220+ unique classes), categorizing hooks into Player Movement/Input, Skinned Model Render, Audio Subsystem, and Fluid Containers.
  * **Pillar 5: Runtime Mod Error & Exception Blame Attribution:** Catches and categorizes silent background exceptions that waste CPU constructing stacktraces: 40+ animation skeleton missing bone errors (`CryOfFearMonsters`, `PZTheMutants`), 40+ missing vehicle script templates (`VanillaVehiclesAnimated`, `KI5campers`), and recurring format string errors (`NeatLockpicking`, `ProjectViewpointNearVegetation`).
  * **Pillar 6: JVM Garbage Collection Churn Velocity:** Measures session duration and Young Gen collection frequency to calculate heap allocation velocity (sweeps/min and pause impact), evaluating whether modpacks suffer from aggressive Lua table allocations and memory churn.
* **🛡️ Savegame Mod ID Whitespace Preservation & Safe Cleanup Bugfix (v2.14.2):**
  * **Critical Savegame Protection in Option [6]:** Fixes a regex truncation flaw in `Invoke-PZCleanSaveMods` and `Invoke-PZScanEngine` where mod IDs containing spaces or punctuation (such as `GanydeBielovzki's Frockin Splendor!`) were truncated at the first space. Completely eliminates false "uninstalled phantom mod" reports and prevents Option [6] from stripping valid installed mods from savegame `mods.txt`.
* **🎯 Viewpoint Situational Trigger Taxonomy & JVM Bytecode Calibration (v2.14.1):**
  * **Granular Situational Gameplay Triggers:** Eliminates misleading blanket `Active: Native JVM Bytecode Execution` labels across all Viewpoint ecosystem sub-mods and ZombieBuddy. Correctly categorizes modules into their exact gameplay triggers: `While Aiming Down Sights (ADS) & Firing` (Project Viewpoint ADS), `While Aiming / Throwing Projectiles` (Advanced Throwables), `While Firing Firearms` (Viewpoint True Ballistics), `During Heavy Storms, Fog & Lightning` (True Weathers), `While Leaning, Prone, Crawling or Vaulting` (Advanced Movement), `Combat Hits & Zombie Damage` (Blood FX), `Near Doors & Doorway Transitions` (Door Fix), `Indoors & Multi-Story Roof Surfaces` (Surface Fix), and `Near Forests & Dense Vegetation` (TREE in 3D).
  * **Elimination of Phantom Cumulative Idle Tax:** Calibrates idle tax for situational JAR mods to `0.00 ms/frame` (since they execute zero per-frame loops when idle on foot), preventing 12+ Viewpoint add-ons from artificially inflating the global modpack idle budget.
  * **Passive Framework Tiering for ZombieBuddy:** Classifies ZombieBuddy as a `Passive Framework` engine (< 1 ms spike, 0.00 ms tax) that executes bytecode class patching at launch time rather than continuous runtime loops, removing it from spike-worthy culprit rosters.
* **🎯 Frame Pacing, Java Bytecode JAR Auditing & Viewpoint Deep Telemetry (v2.14.0):**
  * **Frame Pacing & Headroom Jitter Diagnostic:** Automatically identifies when your configured in-game frame rate cap (`frameRate=240` in `options.ini`) exceeds your simulation CPU throughput (`main thread headroom ~112–139 FPS`), warning about the violent 4ms $\leftrightarrow$ 15ms frame delivery oscillation and the 2x–4x Lua per-frame tick multiplier penalty.
  * **Java Bytecode & Native JAR Mod Auditing (`media/java/client/*.jar` & `libs/*.jar`):** Automatically detects compiled `.jar` modules and ZombieBuddy ASM bytecode transformers, accurately scoring JVM execution overhead and categorizing engine extensions that were previously invisible to Lua-only scanners.
  * **Viewpoint Deep Telemetry Dissection:** Dissects slow frames into granular sub-passes: Main Thread character snapshots (up to 198.4 ms), chunk border meshing (up to 138.5 ms), Render Thread dynamic lamp/sun shadow maps (up to 194.8 ms), G-Buffer passes, floor textures, and render waiting for main thread.
  * **500ms GC Heap Clamp in 1-Click Optimizer (`Invoke-PZFixGC`):** Actively clamps oversized heaps (`-Xmx32g` down to `-Xmx16g`) in `ProjectZomboid64.json`. Eliminates massive 518ms–528ms G1GC pause bursts caused by young-generation accumulation on 32GB allocations.
  * **Engine Exception & Vehicle Spawn Crash Ingestion:** Detects chunk handoff exceptions such as `BaseVehicle.addToWorld NullPointerException: glovebox.container is null` and missing vehicle templates to isolate broken vehicle scripts causing chunk loading freezes.
* **📜 Build 42 Session DebugLog Auto-Discovery & Live Telemetry Ingestion (v2.13.0):** Automatically detects and parses Build 42 active session debug logs (`Zomboid\Logs\<timestamp>_DebugLog.txt`) alongside root `console.txt`, archived session logs (`Logs\logs_*\`), and multiplayer/coop logs. Guarantees live hardware frame times (GPU ms, Render CPU ms, Main Thread ms), loaded zombie entity density, VRAM allocations/PCIe evictions, JVM garbage collection pauses, and recorded slow-frame spikes even when the game is actively running with buffered console logs. Features high-performance non-locking `[System.IO.FileShare]::ReadWrite` streaming for instant reading of 20,000+ line logs (< 80 ms), and adds `-CustomLogPath` parameter for manual log targeting by server administrators.
* **⚡ Idle Baseline vs. Active Burst Tax Telemetry (v2.12.2):** Directly solves player and server admin confusion regarding per-frame loops! Differentiates **Idle Baseline Tax** (the fixed ~0.10 ms Java $\rightarrow$ Lua JNI bridge dispatch cost plus true background scanners) from **Active Burst Tax** (peak worst-case concurrent load during vehicle pushing, driving, or combat). Categorizes all registered per-frame hooks into **Continuous Polling** (e.g. `Cye's Push Doors!` 25-tile spatial scans) vs. **Dormant (Early-Exit)** (e.g. `Take A Bath And Shower`, `Push Vehicle`, `Realistic Dashboard`, `Traits As Skills`, which exit instantly in `< 0.002 ms` when idle on foot). Differentiates semantic risk scoring (12 pts for continuous vs. 4 pts for dormant), correctly scoring dormant mods into Tier 3 / Tier 4 without false critical alarms, and excludes interaction tools like `Push Vehicle` from the drivable vehicle fleet aggregator.
* **🤖 Autonomous NPC AI Simulation Taxonomy (v2.12.0):** Adds specialized classification for NPC behavioral engines (`Project A-Life [ALIFE NPCS]`, `Superb Survivors`, `Bandits`), tagging background sensory perception and state machine loops as `Active: Autonomous NPC AI & Sensory Scanning` with `[AI Simulation Spike]` attribution.
* **🚪 Entity vs. World Tile / Object Query Dissection (v2.12.0):** Splits monolithic world query counters into entity/zombie scans (`getZombieList`, `getCharacters`) and map coordinate queries (`getSquare`, `getGridSquare`). Completely eliminates false `Horde Proximity & Combat` labels on non-combat interaction mods like `Take A Bath And Shower` (plumbing fixture checks) and `Cye's Push Doors!` (door tile checks).
* **🎨 VRAM Saturation vs. 3D Chunk Meshing Precision (v2.12.0):** Distinguishes texture-heavy mods with modest 3D geometry (e.g. `Lifestyle: Hobbies` with 217 MB textures and only 34 meshes) as `VRAM Texture Streaming & Asset Loading (PCIe Thrashing Risk)` rather than chunk traversal lag.
* **🗃️ Universal Container Rebuild & CleanUI Precision (v2.12.0):** Expands heavy container rebuild detection (`refreshBackpacks`, `refreshWeight`) to all inventory overhaul mods (such as `CleanUI`), correctly tagging them as `While Inventory / Container Grid Open` and eliminating false `While in Viewpoint` labels and mod-compatibility helper false opt-ins.
* **📐 Deterministic Continuous Frame Tax Formula Breakdown (v2.11.0):** Transparently exposes the arithmetic constituents of persistent CPU tick tax across every active mod (`Hooks + World Queries + Container Rebuilds + UI Polling + JNI Calls`). Eliminates confusion between static architectural costing and fluctuating runtime profiler sampling, displaying itemized costs in mod detail cards and top CPU tax lists.
* **🏷️ Explicit Loop Ownership Attribution (v2.11.0):** Annotates the global active per-frame loop counter directly with the exact owning mods (e.g. `5 permanent hooks [Push Vehicle (3), Realistic Dashboard (1), Traits As Skills (1)]`), ensuring mod authors and users immediately see which specific mods in the pack own unthrottled tick loops.
* **🚶 Movement-Gated vs. Stationary-Gated Trigger Detection (v2.11.0):** Deeply inspects container rebuilds and heavy logic for standing-still state guards (`not player:isPlayerMoving()`, `not isMoving()`). If guarded, automatically reclassifies the trigger scenario to `Situational: When Standing Still / Stationary (Container Rebuild — Zero Movement Hitch)` and drops the spike rating from Moderate to Low.
* **🔘 Named Opt-In Feature & Hotkey-Toggled Mode Tagging (v2.11.1):** Automatically identifies the exact opt-in mode name (e.g. `Opt-In [All-Containers Mode]: Moving Near Containers (Backpack Rebuild - Unconstrained Movement Hitch)`), clearly signaling to players and mod authors which specific keybind or toggle in the mod settings produces the hitch.
* **🚀 Direct Single-File Release Downloads (v2.11.1):** Zero zip extraction friction! Windows users download `Scan-PZModPerformance.bat` directly as a standalone executable, and Linux/macOS users download `Scan-PZModPerformance.sh` directly.
* **🐧 Linux & 🍎 macOS Universal Compatibility (v2.10.0):** Full cross-platform support with `Scan-PZModPerformance.sh` featuring a 1-click zero-root portable PowerShell Core installer for SteamOS / Steam Deck, Ubuntu, Debian, Fedora, Arch, and macOS.

* **🎯 Granular Situational Trigger Taxonomy & Attribution Precision (v2.8.0):** Replaces generic catch-all "Periodic Timer" labels with 10+ distinct real-world gameplay trigger scenarios. Distinguishes in-vehicle dashboards (`Active: While Inside Vehicle / Driving`), locomotion gear noise (`Situational: While Jogging / Moving on Foot (Gear Audio)`), vehicle shoving (`Situational: While Pushing a Vehicle`), lockpicking minigames (`Situational: While Lockpicking / Mini-Game Active`), post-action tool stowing (`Situational: After Completing Timed Actions (Auto-Stow)`), building cursors (`Situational: While Building / Placing Furniture`), threat line-of-sight checks (`Situational: Threat Proximity & Hostile Alerts`), combat XP gains (`Situational: Combat & XP Gain / Zombie Kills`), gamepad joystick deadzones (`Situational: While Using Controller / Gamepad`), second-screen telemetry (`Situational: Second-Screen Browser Telemetry (~Every 500ms)`), and character creation setup (`Situational: Character Creation & Join (One-Time Setup)`). Corrects false-positive combat attribution on diagnostic logging tools like `ZombieBuddy` down to `< 1 ms [Imperceptible]` passive utility.
* **🎮 State-Gated vs. Continuous Hook Classification (v2.7.1):** Deeply parses Lua execution semantics (`OnTick`, `OnPlayerUpdate`) to distinguish true unconstrained per-frame loops from state-gated hooks that exit immediately via early return when idle (e.g., `if not DragAndDrop.hasPendingCancel then return end`, `if not player:getVehicle() then return end`). Accurately categorizes UI mods (such as `Equipment UI`, `CleanHotBar`, `Neat Crafting`) as `Situational: While Menu / UI Is Open` (+0.02 ms/frame idle) and vehicle mods as `Active: While Driving / Vehicle Streaming`, ensuring mods are never falsely accused of continuous frame drag when menus are closed or when walking on foot.
* **📋 Full Stutter & Lag Spike Impact Roster (v2.7.0):** Clean, 1-line tabular roster displaying every active mod with predicted frame spike bounds, severity status, and exact gameplay trigger events. Replaces visual clutter with unified per-row severity colors (Red for CRITICAL, Yellow for HIGH, DarkYellow for MODERATE, Cyan for LOW, and DarkGray for NEGLIGIBLE). Sorted by impact severity and latency so passive mods always rest at the bottom.
* **🎯 Top 10 Correlated Spike Culprits with Worthiness Filter (v2.7.0):** Deeply correlates recorded engine slow frames across up to the Top 10 highest-impact mods. Implements a strict worthiness filter (`Test-IsSpikeWorthy`) that rejects harmless cosmetic packs and passive `< 1 ms` mods, completely eliminating blind padding.
* **🧱 World / Chunk Geometry vs. Character Skinned Mesh Differentiation (v2.7.0):** Accurately distinguishes world tile/chunk geometry and vehicle meshes (`media/voxel-studio/`, `models_X/World`, vehicle definitions) from character attachments (`media/clothing`, `models_X/Skinned`, hair). Character cosmetic mods are never falsely accused of causing chunk cache rebuild stalls or given unfair risk penalties.
* **🩺 Precision Slow Frame Anatomy Dissection (v2.5.0):** Dissects every slow-frame log line in Build 42 into its component sub-stalls:
  * **Main vs. Render Thread Origin:** Distinguishes CPU simulation freezes from GPU draw stalls.
  * **Java GC Pauses vs. Chunk Meshing:** Measures the exact millisecond pause caused by JVM garbage collection sweeps (`the collector's pauses`) versus geometry compilation (`chunk cache builds`).
  * **Actionable Root Cause:** Pinpoints whether a spike requires JVM G1GC tuning (Option `[4]`) or custom 3D model trimming.
* **🛡️ Causal Bottleneck Filtering (Zero False Mod Accusations):** Prevents innocent Lua UI or QOL mods from being falsely blamed for world hitches. If an engine freeze is caused by Java GC sweeps or chunk meshing, the suite attributes the stall directly to JVM memory or 3D mesh packs, keeping QOL mod ratings clean and accurate.
* **⏱️ Hardware Frame Times & Simulation Headroom:** Extracts real-time GPU render times, Render CPU frame times, and Main Thread simulation duration (`main thread frame 9.70 ms -> 103 FPS headroom`) alongside active loaded zombie counts.
* **🔗 Multi-Culprit Telemetry Correlation Engine:** Deeply correlates recorded engine telemetry from `console.txt` across multiple bottleneck vectors:
  * **Frame Hitch Culprits:** Identifies and ranks up to the top 10 worthy mods contributing to the worst recorded frame spike with predicted freeze durations and trigger events.
  * **GPU VRAM Thrashing Attributions:** Identifies the top texture heavyweights responsible for saturated VRAM and PCIe bus paging freezes.
  * **Chunk Cache Hitching:** Surfacing only legitimate world 3D mesh injectors causing chunk rebuild stalls during world traversal.
  * **Continuous CPU Tick Drag:** Isolates the top mods burning frame budget every single tick, accurately scaling queries in throttled/periodic hooks.
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
   PROJECT ZOMBOID MOD PERFORMANCE & OPTIMIZATION SUITE v2.8.0  
         Created by @KodeMannn with the help of Gemini          
=================================================================

 [INFO] Detected Game Version: 42.21.0
 [INFO] Active Savegame: Outbreak / 2026-10-05_05-24-34
 [INFO] Total Enabled Mods to Audit: 74

-----------------------------------------------------------------
   RUNTIME ENGINE TELEMETRY SUMMARY
-----------------------------------------------------------------
 Configured Frame Cap : 240 FPS (Active: 240 FPS)
 Hardware Frame Times : GPU: 8.48 ms | Render CPU: 8.01 ms | Main Thread: 9.16 ms (~109 FPS cap)
 Live World Simulation: 84 active zombies loaded in simulation radius (109 in-game FPS)
 GPU VRAM Usage       : 978 MB free of 12282 MB
   [!] GPU Thrashing  : 385 texture evictions (1641 MiB swapped across PCIe)!
       Cause & Impact : VRAM saturated; PCIe texture swapping causes 100-250ms render hitching
       Top VRAM Loads : 6261 3D models for Viewpoint (170.79 MB), Realistic Dashboard and Gauges (50.18 MB)
 Java Heap Allocation : 3470 MB used of 9792 MB
 JVM Garbage Collector: 0 Old Gen Freezes | Young Gen: 150 sweeps (avg 8.3 ms, 1246 ms total)
 Slow Frames (>50ms)  : 44 recorded in last session
 Worst Frame Spike    : 717.5 ms (RENDER THREAD)
   -> SPIKE ANATOMY   : 709.3 ms Waiting for Main Thread (98.9%) | 8.2 ms Render Passes (1.1%)
   -> ROOT CAUSE      : GPU Render Thread Blocked Waiting for CPU Main Thread Tick
   -> ATTRIBUTION     : Main thread CPU tick budget overflow from excessive per-frame Lua loops.
   -> ACTIONABLE FIX  : Lower in-game frame rate cap to 120 FPS (Option [5]) or reduce vehicle fleet mods.
   -> TOP CORRELATED SPIKE CULPRITS (Up to Top 10 High/Moderate Impact):
      [01] 6261 3D models for Viewpoint ... | Pred: ~350-550 ms [Severe Freeze]  | Chunk Border Traversal & High-Speed Driving
      [02] Project Viewpoint QOL            | Pred: ~10-35 ms [Combat Hitch]     | Horde Proximity & Combat
      [03] Push Vehicle                     | Pred: ~5-15 ms [Minor Blip]        | Situational: While Pushing a Vehicle
      [04] Tidy Up Meister                  | Pred: ~5-15 ms [Minor Blip]        | Situational: After Completing Timed Actions (Auto-Stow)
      [05] Construction 1P Viewpoint        | Pred: ~5-15 ms [Minor Blip]        | Situational: While Building / Placing Furniture
      [06] Viewpoint Threat Detector        | Pred: ~5-15 ms [Minor Blip]        | Situational: Threat Proximity & Hostile Alerts
      [07] Realistic Dashboard and Gauges   | Pred: ~5-15 ms [Minor Blip]        | Active: While Inside Vehicle / Driving
      [08] Dynamic Gear Rattling            | Pred: ~5-15 ms [Minor Blip]        | Situational: While Jogging / Moving on Foot (Gear Audio)
      [09] Spongie's Character Customisa... | Pred: ~5-15 ms [Minor Blip]        | Situational: Character Creation & Join (One-Time Setup)
      [10] Neat Lockpicking                 | Pred: ~5-15 ms [Minor Blip]        | Situational: While Lockpicking / Mini-Game Active
 Chunk Cache Hitches  : Up to 173 mesh builds/chunk (Peak rebuild stall: 10.9 ms)
   -> Top 3D Meshes   : 6261 3D models for Viewpoint (10241 world meshes), that DAMN Library (46 world meshes)
 File Override Clashes: 433 detected (431 Safe, 2 High/Moderate Risk)

-----------------------------------------------------------------
   GLOBAL MODPACK RUNTIME BUDGET & LOOP DENSITY
-----------------------------------------------------------------
 Cumulative Mod Frame Tax : +1.26 ms/frame (Continuous CPU tick overhead)
 Active Per-Frame Loops   : 0 permanent hooks firing every single frame
 Total Custom 3D Models   : 10904 meshes (414.48 MB textures across mods)
   -> Top CPU Tick Tax: Project Viewpoint QOL (+0.2 ms/frame), Push Vehicle (+0.11 ms/frame), Construction 1P Viewpoint (+0.05 ms/frame)

 [MASS VEHICLE FLEET WARNING] 19 vehicle mods active (4 state-gated hooks)!
         Vehicle mods register per-frame speed/gauge hooks (e.g. DorothyAnemometer).
         Combined, your vehicle fleet contributes +0.08 ms/frame overhead & 352 meshes.
         Recommendation: Trim vehicle mods you aren't currently driving.

-----------------------------------------------------------------
   ACTIVE MODS RANKED BY STUTTER & LAG SPIKE POTENTIAL
   (Worst-case burst prediction & trigger scenario across all active mods)
-----------------------------------------------------------------
  Rank Mod Name                         | Spike Potential (Predicted Burst)  | Trigger Scenario
 ----- -------------------------------- | ---------------------------------- | -----------------------------------
 [01]  6261 3D models for Viewpoint ... | Pred: ~350-550 ms [Severe Freeze]  | Chunk Border Traversal & High-Speed Driving
 [02]  Project Viewpoint QOL            | Pred: ~10-35 ms [Combat Hitch]     | Horde Proximity & Combat
 [03]  Push Vehicle                     | Pred: ~5-15 ms [Minor Blip]        | Situational: While Pushing a Vehicle
 [04]  Tidy Up Meister                  | Pred: ~5-15 ms [Minor Blip]        | Situational: After Completing Timed Actions (Auto-Stow)
 [05]  Construction 1P Viewpoint        | Pred: ~5-15 ms [Minor Blip]        | Situational: While Building / Placing Furniture
 [06]  Viewpoint Threat Detector        | Pred: ~5-15 ms [Minor Blip]        | Situational: Threat Proximity & Hostile Alerts
 [07]  Realistic Dashboard and Gauges   | Pred: ~5-15 ms [Minor Blip]        | Active: While Inside Vehicle / Driving
 [08]  Dynamic Gear Rattling            | Pred: ~5-15 ms [Minor Blip]        | Situational: While Jogging / Moving on Foot (Gear Audio)
 [09]  Spongie's Character Customisa... | Pred: ~5-15 ms [Minor Blip]        | Situational: Character Creation & Join (One-Time Setup)
 [10]  Neat Lockpicking                 | Pred: ~5-15 ms [Minor Blip]        | Situational: While Lockpicking / Mini-Game Active
 [11]  Project Viewpoint Controller ... | Pred: ~5-15 ms [Minor Blip]        | Situational: While Using Controller / Gamepad
 [12]  Traits As Skills                 | Pred: ~5-15 ms [Minor Blip]        | Situational: Combat & XP Gain / Zombie Kills
 [13]  More Damaged Objects             | Pred: ~5-15 ms [Minor Blip]        | Situational: Damaged Object Sprites & Water Animations
 [14]  PZ Pulse                         | Pred: ~5-15 ms [Minor Blip]        | Situational: Second-Screen Browser Telemetry (~Every 500ms)
 [15]  Equipment UI - [Standalone]      | Pred: ~2-8 ms [Frame Delay]        | Situational: While Menu / UI Is Open
 [16]  CleanHotBar                      | Pred: ~2-8 ms [Frame Delay]        | Situational: While Menu / UI Is Open
 ...
 [58]  ZombieBuddy                      | Pred: < 1 ms [Imperceptible]       | None (Passive / Static UI)
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
