# World of Destruction — Roblox Edition

An open-world 3D vehicular destruction sandbox built in Luau for **Roblox Studio**.

> **Idealized by:** Leo Bigliassi (age 7)  
> **Developed by:** Marcelo Bigliassi

Drive across **Leo City**, smash through fire hydrants, fences, street lights, supply crates, bus stops, snack kiosks, billboards, and explosive gas pumps, build up massive **×20 Destruction Combos**, outrun (or wreck!) **5-star Police Pursuits**, and spend your Destruction Cash at the **Speed Shop** to unlock 8 vehicles (from the nimble *Compact Hatch* and *Thunder V8 Muscle* up to the *Crusher XL Monster Truck* and *Rampage Demolition Tank*) and 5 upgrade tracks!

---

## Quick Start: Opening & Testing in Roblox Studio

There are two ways to open and play **World of Destruction** in Roblox Studio:

### Option A: Open `WorldOfDestruction.rbxlx` Directly (Fastest — Zero Setup)

1. Launch **Roblox Studio**.
2. Click **File → Open from File...** (or press `Cmd + O` on macOS / `Ctrl + O` on Windows).
3. Select `Roblox/WorldOfDestruction.rbxlx`.
4. Press **Play (`F5`)** to jump straight into Leo City!

---

### Option B: Live Sync with Rojo (Recommended for Development)

If you want to edit the `.luau` source files in Cursor / VS Code and sync changes live into Roblox Studio:

1. **Install Rojo** (v7.4+):
   - Via Rokit / Aftman / Foreman, or Homebrew on macOS:
     ```bash
     brew install rojo
     ```
2. **Start the Rojo Dev Server**:
   ```bash
   cd Roblox
   rojo serve default.project.json
   ```
3. **Connect from Roblox Studio**:
   - Open Roblox Studio (either a new Baseplate or `WorldOfDestruction.rbxlx`).
   - In the **Plugins** tab, open the **Rojo** plugin and click **Connect** (`localhost:34872`).
4. **(Optional) Build the standalone `.rbxlx` place file from CLI**:
   ```bash
   cd Roblox
   rojo build default.project.json -o WorldOfDestruction.rbxlx
   ```

---

## Controls

| Action | Keyboard / Mouse | Gamepad | Touch / UI |
|---|---|---|---|
| **Throttle / Brake & Reverse** | `W` / `S` or `Up` / `Down` | `R2` / `L2` | On-screen Pedals |
| **Steer Left / Right** | `A` / `D` or `Left` / `Right` | Left Stick | Steer Buttons |
| **Nitro Boost** | `Left Shift` or `Space` | `Button A` / `Button X` | **NITRO** Button |
| **Handbrake / Drift** | `E` or `Left Control` | `Button B` | **DRIFT** Button |
| **Spawn / Reset Vehicle** | `R` | `Button Y` | **SPAWN / REPAIR** HUD Button |
| **Open Garage & Speed Shop** | `G` | `DPad Up` | **GARAGE** HUD Button |
| **Exit / Enter Vehicle** | `F` | `DPad Down` | Roblox Seat / HUD Button |

---

## Project Architecture (`src/`)

```text
Roblox/
├── default.project.json               # Rojo project mapping
├── WorldOfDestruction.rbxlx           # Standalone Roblox Studio place file
├── README.md                          # This guide
└── src/
    ├── ReplicatedStorage/
    │   └── Shared/
    │       ├── GameConfig.luau        # Central balance & tuning (vehicles, props, combos, police, upgrades, city)
    │       ├── Types.luau             # Shared Luau strict type definitions
    │       └── Remotes.luau           # Auto-provisioned ReplicatedStorage.Remotes events & functions
    ├── ServerScriptService/           # Server-side city generation, vehicle physics, destruction, economy & police AI
    ├── StarterPlayer/
    │   └── StarterPlayerScripts/      # Client vehicle controls, camera shake, VFX/SFX & debris particles
    └── StarterGui/                    # HUD (Cash, Combo meter, Wanted Stars, Speedometer, Garage & Upgrade Shop)
```

---

## Core Systems Overview

- **8 Vehicle Classes**: `Compact` (Starter), `Sedan`, `Pickup`, `Muscle`, `SUV`, `Sports`, `MonsterTruck`, and `Tank`.
- **8 Destructible Tiers**: `Hydrant` (with water geyser), `Fence`, `Crate`, `StreetLight`, `BusStop`, `Kiosk`, `Billboard`, and explosive `GasPump` (triggers area-of-effect blast damage).
- **Combo Multiplier System**: Chaining hits within `3.5s` scales rewards from `×1` → `×2` → `×3` → `×5` → `×8` → `×12` → `×20`, plus a `25%` completion bonus when the combo finishes.
- **5-Star Police Heat System**: Escalates from `Cruiser` patrols at 1–2★ to `Interceptor` units at 3★, `SWATVan` roadblocks at 4★, and heavy `Enforcer` units at 5★. Players can ram police cars to wreck them or escape to the **Hideout Garage**.
- **Garage Upgrades**: 5 tracks × 5 levels (`Engine`, `Armor`, `Nitro`, `Plow`, `CashMagnet`).
