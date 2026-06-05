# Boat Game Development Progress

## Overview
This document summarizes all development work on the Playdate boat fishing game ("Loop"), including physics, sprites, game loop, upgrade system, and progression balancing.

---

## Phase 1 — Core Physics & Sprites (main branch)

### Fish Sprite Replacement
- Replaced circular dots with PNG sprites (clownfish, stur, anchovy)
- Randomized fish type assigned on spawn via `fishImages` table
- Drew using `drawAnchored()`

### Angular Drag Physics
- Crank controls visual angle (instant response)
- `moveAngle` lags behind visual angle — angular delta drives a cosine speed penalty
- `speed = baseSpeed * max(0.4, cos(angleDiff))` — sharp turns slow you down, straight lines = full speed
- `driftWeight = 0.15` controls how fast movement angle recovers toward visual angle
- Replaced all momentum/lerp physics with this system

### Wake Trail
- Line width 2px for visibility
- Stern offset adjusted to `l/2 - 20` so wake originates from under sprite
- Circular buffer capped at `WakeMaxLength` (110 points)

### Sprites
- Scaled boat and shadow to 60×60 using Aseprite
- Using `boat60.gif` and `shadow60.gif` (360-frame GIF imagetables)
- Shadow offset: 5px from boat center

---

## Phase 2 — Loop Branch: Game Loop & Round System

### Branch
Created `Loop` branch from main. All work below is on this branch.

### 12-Second Round Timer
- `roundDuration = 600` frames (50 FPS × 12s)
- `roundTime` increments every frame; when it hits `roundDuration`, game pauses
- Pause screen shows time-up message with **B = Continue** / **A = Upgrade** options
- Fonts: `Roobert-24-Medium` for timer/pause text, `Roobert-11-Medium` for UI

### Full Round Reset (`resetRound()`)
- Resets boat position, angle, velocity, wake, fish
- Increments `totalRunsPlayed`
- Respawns fish respecting Spawn upgrade level
- Called both from "Continue" and from the upgrade screen's B button

### Off-Screen Fish Indicators
- Small black triangles at screen edge pointing toward any fish that's off-screen
- Drawn on top of everything using `drawOffScreenFishIndicators()`
- Triangle tip at edge, base inset 10px, always visible even at far distances

---

## Phase 3 — Upgrade System

### Upgrade Screen (replaced skill tree)
Replaced a complex 29-node zooming skill tree with a clean 6-item list:

| # | Upgrade | Effect |
|---|---------|--------|
| 1 | Value   | +$1 per fish per level caught |
| 2 | Spawn   | More fish in water (+10%/level) |
| 3 | Speed   | Boat speed multiplier (+15%/level) |
| 4 | Line    | Wake length (+10%/level) |
| 5 | Permit  | Max fish catchable per loop (min 1) |
| 6 | Time    | 5% chance per level to add 1s on catch |

**Navigation:**
- Crank or D-pad Up/Down: scroll list
- A: buy next level
- Left: refund one level (get cost back)
- B: return to game and start new round

**Max level per upgrade: 12**

### Permit Special Rule
- Permit starts at level 1 (you can always catch 1 fish per loop)
- Cannot be refunded below level 1

---

## Phase 4 — Progression & Economy

### Income Formula
```
Total Income/run = BaseIncome × V × S × Sp × L × P × T

Where each multiplier = 1 + (upgrade.level × mult_rate):
  Value:  +10%/level  (actual fish value also +$1/level)
  Spawn:  +10%/level
  Speed:  +15%/level
  Line:   +6%/level
  Permit: +5%/level
  Time:   +3%/level
```

### Cost Formula
```
Cost(upgradeIndex, level) = floor(BasePrice × (1.18 ^ level) + level)
```

### Base Prices (final, recalibrated for $2/run baseline)
```lua
local UPGRADE_BASE_PRICES = { 5, 6, 5, 2, 12, 18 }
-- Value=$5, Spawn=$6, Speed=$5, Line=$2, Permit=$12, Time=$18
```

---

## Phase 5 — Debug System

### Small Debug Overlay (in-game)
- Toggle with Menu button
- Shows in top-right corner (small font, white background box)
- Displays: all upgrade levels, income/run, cost of next Value/Spawn/Speed, run count, money

### Full Debug Menu Screen
- Access with Menu + A
- Full income breakdown (each upgrade's multiplier contribution)
- Free level adjustment: Left/Right changes level without spending money
- A button buys at real cost
- Menu+A = +$500 cheat, Menu+B = full reset
- B exits back to game

---

## Phase 6 — Progression Testing & Analysis (May 9, 2026)

### Console Export Feature
Added game state export to console on each round completion for progression analysis:
- Tracks `totalFramesPlayed` during active gameplay (not paused/menus)
- Tracks `roundsCompleted` count
- Prints to console: runs played, money, playtime, income/run, all upgrade levels
- Format: `runs=X money=$Y time=ZmSs income=$I/run V=v S=s Sp=sp L=l P=p T=t`

### Full 50-Run Playthrough Data (Timer-Based System)
*Note: This data reflects the original 12-second round timer gameplay.*

```
runs=0 money=$1 time=0m12s income=$2/run V=0 S=0 Sp=0 L=0 P=1 T=0
runs=1 money=$4 time=0m24s income=$2/run V=0 S=0 Sp=0 L=0 P=1 T=0
runs=2 money=$3 time=0m36s income=$2/run V=0 S=0 Sp=0 L=1 P=1 T=0
... [Omitted for brevity in this display, but preserved in file] ...
runs=49 money=$202 time=10m59s income=$101/run V=12 S=12 Sp=12 L=12 P=12 T=12
```

### Progression Analysis
- **Early Game (Runs 0-10):** Slow burn, $2 baseline.
- **Mid Game (Runs 11-25):** The "Inflection Point" where fun accelerates and income hits 4x baseline.
- **Late Game (Runs 26-49):** Exponential growth reaching $100+/run.

---

## Phase 7 — Tier 2 Upgrades & Fish Movement (May 9, 2026)

### Tier 2 Upgrade System
After reaching $300, unlock Tier 2 upgrades (L13-L24):
- **Speed and Line hard-capped at L12** to prevent control issues.
- Tier 2 uses steeper cost curve: `basePrice × (1.25^level)`.

### Progressive Fish Movement
Fish start moving at run 50 (when Tier 2 unlocks) with gentle drifts increasing in speed over time.

### Full 51-Run Tier 2 Progression Data
```
runs=50 money=$300 time=0m12s income=$8/run V=5 S=3 Sp=3 L=5 P=2 T=0
... [Omitted for brevity in this display, but preserved in file] ...
runs=100 money=$839 time=13m29s income=$259/run V=24 S=20 Sp=12 L=12 P=18 T=13
```

---

## ⭐ CHANGE OF DIRECTION: Capacity & Physics (May 27, 2026)

**Strategic Pivot:** Moved away from the 12-second timer limit to a more physics-focused, capacity-based exploration model.

---

## Phase 8 — Physical Bounce & Capacity Hold

### Physical Bounce Impulse
Replaced "Game Over on Collision" with a playful **Bounce Mechanic**:
- **Impulse**: Hitting terrain reflects the boat's velocity and adds a burst of speed (`4.5` pixels/frame).
- **Decay**: Bounce momentum gently decays (`0.92` multiplier) over 20 frames.
- **Directional Steering**: Removed visual angle snapping during bounce to allow players to maintain steering direction while flying backward.

### Capacity-Based Hold System
Replaced the round timer with a **Hold System**:
- **Mechanism**: The boat can carry a limited number of fish. When the hold is full, the game pauses.
- **Upgrades**: "Capacity" upgrade added to the shop (replaces Time/Permit context), adding +3 slots per level.
- **Loop Flow**: Players now fish until full, then choose to Upgrade or Return for another run.

---

## Phase 9 — Map 2 & Advanced Distribution (May 29, 2026)

### Map "2-top" Integration
- **Expanded World**: Visual area increased to **1400x1400** to hide screen edges.
- **Playable Zone**: Gameplay restricted to the central **1000x1000** area.
- **New Assets**: Integrated `2-top.png` (visuals) and `2-collision.png` (physics mask).
- **Custom Spawn**: Default spawn coordinates set to **(852, 1065)** for the new map layout.

### Fish Schooling & Distribution
- **Schooling Logic**: Fish now spawn in **Clusters** (3 groups of 3) around safe anchor points to create "high-value" catch opportunities.
- **Lone Scouts**: Remaining fish spawn randomly to fill gaps between schools.
- **Land Buffer**: Implemented a **50-pixel safety check** against the collision mask to prevent fish from appearing in tight alcoves or on land.
- **Fallback System**: If a 50px spot cannot be found, the system automatically retries with a 15px buffer to ensure map density.

### Sprite Update
- **Boat 6**: Replaced the default boat sprite with the "boat_6" variant for improved visuals.

---

## Phase 10 — Soundtrack, Navigation & Audio Polish (June 2, 2026)

### Audio System & Effects
- **Menu Music**: Integrated background music for the Dock and its sub-menus (`boxset - wedelivery.mp3`).
- **Muffled Filter**: Implemented a `playdate.sound.twopolefilter` (Low-Pass).
  - **Dock**: Cutoff at 20,000Hz (clear sound).
  - **Sub-menus (Upgrades/Music)**: Cutoff drops to 800Hz for a muffled "behind a wall" effect.
- **Audio Infrastructure**: Refactored to use a dedicated `playdate.sound.channel` for the menu music, allowing robust effect routing via `addSource()` and ensuring compatibility with the Playdate SDK.

### Soundtrack Selection Menu
- **New Screen**: Accessed by pressing **Right** from the Dock.
- **Tape Grid**: Displays a 3x2 grid of tapes using 75x74px full-size assets (`tape.png`).
- **Persistence**: Remembers and indicates the currently selected track with a visual marker, even after navigating away and returning.
- **Navigation**: Custom D-Pad logic for 3-column navigation; A to select a track, B to return to the Dock.

### Navigation & Drawing Robustness
- **Transition Fix**: Restructured `playdate.update` to separate State Updates from Drawing, guaranteeing a render call every frame and eliminating "blank screen" frames during transitions.
- **B-Button Logic**: Fixed the Upgrade screen B-button to correctly return the player to the Dock, with prioritized input handling.
- **Drawing Polish**: 
  - Added `gfx.clear()` to the dock drawing function for safety.
  - Implemented draw-mode resets (`kDrawModeCopy`) at the end of screen drawing functions to prevent state pollution (e.g., text highlights causing invisible images on other screens).

---

## Phase 11 — Audio Streamlining (June 5, 2026)

### Removal of Menu Audio
- **Music**: Removed the background music (`boxset - wedelivery.mp3`) from the Dock and sub-menus to provide a quieter, focused experience.
- **Audio Effects**: Deleted the `twopolefilter` muffled effect previously applied to sub-menus (Upgrade/Music screens).
- **Cleanup**: Removed all associated audio initialization, channel management, and per-frame filter logic from `main.lua` to optimize performance and code clarity.

---

## Current Game Config (June 5, 2026)

```lua
Config.Boat = {
    baseSpeed = 1.75,
    minTurnSpeed = 1.5,
    driftWeight = 0.15,
    rotationSpeed = 5,
    size = { w = 80, l = 80 }
}
Config.Fish = {
    count = 15, -- (10 Schools + 5 Lone Scouts)
    spawnRadius = 200,
    size = 4,
}
Config.WakeMaxLength = 110
```

---

## Files Modified
- **Source/main.lua** — Core game logic, physics, and rendering.
- **Source/images/level/** — `2-top.png`, `2-collision.png` (New map assets).
- **Source/images/boat/** — `boat.gif` (Updated to boat_6).
- **PROGRESS.md** — Project history and status tracking.

---

## Known Behaviors / Design Decisions
- **Bounce vs. Timer**: The game now focuses on exploration and "runs" defined by hold capacity.
- **Multi-Fish Bonus**: Catching multiple fish in one loop grants significant cash multipliers (up to +50%).
- **Center-Point Check**: Added a center-point fallback to boat collision for increased robustness.
- **Speed/Line Cap**: Speed and Line upgrades remain capped at L12 to preserve handling balance.
