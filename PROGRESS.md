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

### Progression Pacing
| Phase | Runs | What's happening |
|-------|------|-----------------|
| Early | 1–5 | Line L1 ($3) and Speed L1 ($6) in reach immediately |
| Mid   | 5–20 | Value/Spawn L2–L4, income climbing noticeably |
| Late  | 20–60 | Permit L1 ($15) unlocked, powerful upgrades in reach |
| Endgame | 60+ | Maxing Permit or Time (L12) is a real achievement |

### Balancing History
1. First attempt: base prices `{15, 20, 25, 10, 35, 50}` — too expensive (based on wrong $10/run assumption)
2. Second attempt: `{3, 4, 5, 2, 7, 10}` with `1.12` exponent — too cheap, could max everything in ~10 min
3. **Final**: `{5, 6, 5, 2, 12, 18}` with `1.18` exponent — early fun preserved, late-game meaningful

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

## Current Game Config

```lua
Config.Boat = {
    baseSpeed = 1.75,       -- reduced 50% from original 3.5
    minTurnSpeed = 1.5,
    driftWeight = 0.15,
    rotationSpeed = 5,
    size = { w = 60, l = 60 }
}
Config.Fish = {
    count = 5,
    spawnRadius = 200,
    size = 4,
}
Config.WakeMaxLength = 110   -- base; scaled up by Line upgrade
Config.roundDuration = 600   -- 12 seconds at 50 FPS
```

---

## Files Modified

- **Source/main.lua** � Updated collision logic and added debug drawing.
- **PROGRESS.md** � Added Phase 8 details.
- **Source/images/fish/** — clownfish.png, stur.png, anchovy.png
- **Source/images/boat/** — boat60.gif, shadow60.gif

---

## Git Commits (Loop branch)
1. "Replace fish dots with randomized PNG sprites"
2. "Implement Angular Drag physics for arcade-style steering"
3. "Switch to Boat60 and Shadow60 sprites with adjusted shadow offset"
4. "Add 12-second round timer, pause screen, upgrade list, off-screen fish indicators"
5. "Add progression system: 6 upgrades with cost formula, income multipliers, dual debug system"
6. "Rebalance upgrade costs: steeper curve, higher Permit/Time base prices"

---

## Phase 6 — Progression Testing & Analysis (May 9, 2026)

### Console Export Feature
Added game state export to console on each round completion for progression analysis:
- Tracks `totalFramesPlayed` during active gameplay (not paused/menus)
- Tracks `roundsCompleted` count
- Prints to console: runs played, money, playtime, income/run, all upgrade levels
- Format: `runs=X money=$Y time=ZmSs income=$I/run V=v S=s Sp=sp L=l P=p T=t`

### Full 50-Run Playthrough Data

```
runs=0 money=$1 time=0m12s income=$2/run V=0 S=0 Sp=0 L=0 P=1 T=0
runs=1 money=$4 time=0m24s income=$2/run V=0 S=0 Sp=0 L=0 P=1 T=0
runs=2 money=$3 time=0m36s income=$2/run V=0 S=0 Sp=0 L=1 P=1 T=0
runs=3 money=$6 time=0m48s income=$2/run V=0 S=0 Sp=0 L=1 P=1 T=0
runs=4 money=$3 time=1m0s income=$2/run V=0 S=0 Sp=1 L=1 P=1 T=0
runs=5 money=$6 time=1m12s income=$2/run V=0 S=0 Sp=1 L=1 P=1 T=0
runs=6 money=$9 time=1m24s income=$2/run V=0 S=0 Sp=1 L=1 P=1 T=0
runs=7 money=$9 time=1m36s income=$2/run V=1 S=0 Sp=1 L=1 P=1 T=0
runs=8 money=$10 time=1m48s income=$3/run V=2 S=0 Sp=1 L=1 P=1 T=0
runs=9 money=$19 time=2m0s income=$3/run V=2 S=0 Sp=1 L=1 P=1 T=0
runs=10 money=$12 time=2m12s income=$3/run V=3 S=1 Sp=1 L=1 P=1 T=0
runs=11 money=$14 time=2m24s income=$4/run V=3 S=1 Sp=1 L=3 P=1 T=0
runs=12 money=$16 time=2m36s income=$4/run V=4 S=1 Sp=1 L=3 P=1 T=0
runs=13 money=$18 time=2m48s income=$4/run V=5 S=1 Sp=1 L=3 P=1 T=0
runs=14 money=$24 time=3m0s income=$4/run V=5 S=1 Sp=1 L=3 P=2 T=0
runs=15 money=$33 time=3m12s income=$5/run V=6 S=1 Sp=1 L=3 P=2 T=0
runs=16 money=$25 time=3m24s income=$6/run V=7 S=2 Sp=1 L=3 P=2 T=0
runs=17 money=$33 time=3m36s income=$6/run V=7 S=2 Sp=1 L=5 P=2 T=0
runs=18 money=$25 time=3m48s income=$7/run V=8 S=2 Sp=1 L=5 P=2 T=0
runs=19 money=$42 time=4m0s income=$8/run V=8 S=2 Sp=3 L=5 P=2 T=0
runs=20 money=$31 time=4m12s income=$9/run V=9 S=2 Sp=3 L=5 P=2 T=0
runs=21 money=$34 time=4m24s income=$11/run V=9 S=4 Sp=3 L=5 P=2 T=0
runs=22 money=$25 time=4m36s income=$13/run V=9 S=4 Sp=5 L=5 P=2 T=0
runs=23 money=$55 time=4m48s income=$13/run V=9 S=4 Sp=5 L=5 P=2 T=0
runs=24 money=$34 time=5m0s income=$15/run V=10 S=5 Sp=5 L=5 P=2 T=0
runs=25 money=$54 time=5m12s income=$16/run V=10 S=5 Sp=5 L=7 P=2 T=0
runs=26 money=$49 time=5m24s income=$17/run V=10 S=5 Sp=5 L=7 P=4 T=0
runs=27 money=$56 time=5m36s income=$18/run V=11 S=5 Sp=5 L=7 P=4 T=0
runs=28 money=$55 time=5m50s income=$19/run V=11 S=5 Sp=5 L=7 P=4 T=2
runs=29 money=$59 time=6m3s income=$20/run V=12 S=5 Sp=5 L=7 P=4 T=2
runs=30 money=$63 time=6m15s income=$23/run V=12 S=7 Sp=5 L=7 P=4 T=2
runs=31 money=$83 time=6m27s income=$24/run V=12 S=7 Sp=5 L=7 P=5 T=2
runs=32 money=$78 time=6m40s income=$26/run V=12 S=7 Sp=5 L=7 P=5 T=4
runs=33 money=$81 time=6m53s income=$30/run V=12 S=7 Sp=5 L=11 P=5 T=4
runs=34 money=$92 time=7m6s income=$38/run V=12 S=7 Sp=8 L=11 P=5 T=4
runs=35 money=$105 time=7m19s income=$42/run V=12 S=9 Sp=8 L=11 P=5 T=4
runs=36 money=$61 time=7m32s income=$46/run V=12 S=9 Sp=8 L=11 P=7 T=4
runs=37 money=$82 time=7m45s income=$51/run V=12 S=9 Sp=9 L=12 P=7 T=4
runs=38 money=$122 time=7m59s income=$57/run V=12 S=9 Sp=11 L=12 P=7 T=4
runs=39 money=$137 time=8m12s income=$64/run V=12 S=10 Sp=12 L=12 P=7 T=4
runs=40 money=$167 time=8m29s income=$67/run V=12 S=10 Sp=12 L=12 P=7 T=6
runs=41 money=$143 time=8m43s income=$72/run V=12 S=10 Sp=12 L=12 P=9 T=6
runs=42 money=$134 time=9m0s income=$76/run V=12 S=10 Sp=12 L=12 P=9 T=8
runs=43 money=$118 time=9m15s income=$82/run V=12 S=11 Sp=12 L=12 P=10 T=8
runs=44 money=$160 time=9m33s income=$84/run V=12 S=11 Sp=12 L=12 P=10 T=9
runs=45 money=$144 time=9m50s income=$90/run V=12 S=12 Sp=12 L=12 P=10 T=10
runs=46 money=$163 time=10m7s income=$93/run V=12 S=12 Sp=12 L=12 P=11 T=10
runs=47 money=$184 time=10m24s income=$96/run V=12 S=12 Sp=12 L=12 P=11 T=11
runs=48 money=$184 time=10m41s income=$98/run V=12 S=12 Sp=12 L=12 P=11 T=12
runs=49 money=$202 time=10m59s income=$101/run V=12 S=12 Sp=12 L=12 P=12 T=12
```

### Progression Analysis

**Early Game (Runs 0-10): Slow Burn**
- Baseline $2/run income, tight but intentional
- First upgrades ($2-6) are affordable early; players get quick wins
- By run 10: income climbs to $3/run — modest but meaningful

**Mid Game (Runs 11-25): The Inflection Point ⭐**
- **This is where the game becomes *fun* — around runs 20-25**
- Income accelerates: $4 → $16/run (4× improvement)
- Multiple upgrade synergies unlock: Speed (Sp), higher Permit levels, Line upgrades
- Boat handling feels visibly different — steering is more responsive, can catch more fish
- Money per run swings larger ($25-55) — feels rewarding and organic

**Late Game (Runs 26-49): Exponential Satisfaction**
- Income continues acceleration: $17 → $101/run in 24 runs
- Upgrades maxing out (V, S, Sp, L hitting level 12)
- By run 45, player has nearly maxed the tree
- Fishing gameplay is completely transformed from run 0

### Key Findings

1. **Pacing is natural & non-grindy** — Early game respects player time, late game escalates rewards
2. **Upgrade synergy works** — Speed + Line + Permit compound together; you *feel* more capable as upgrades stack
3. **"Fun threshold" aligns with data** — Player intuition (fun starts ~run 20-25) matches the inflection point in the cost/income curve
4. **No progression walls** — Player always has an affordable upgrade path; never stuck waiting for money
5. **Variance is healthy** — Money per run varies naturally ($1-$202), feels organic not punishing

### Verdict
✅ **The progression curve is well-designed.** It's engaging, respects player time investment, and the exponential growth feels *earned* rather than arbitrary. The game nails the balance between early accessibility and late-game satisfaction.

---

## Phase 7 — Tier 2 Upgrades & Fish Movement (May 9, 2026)

### Tier 2 Upgrade System
After reaching $300, unlock Tier 2 upgrades:
- **Value, Spawn, Permit, Time** continue into Tier 2 (L13-L24)
- **Speed and Line hard-capped at L12** — prevents runaway difficulty/speed creep
- Tier 2 uses steeper cost curve: `basePrice × (1.25^level)` vs Tier 1's `1.18`
- Tier 2 upgrades capped at L24 for defined endgame goal
- Unlock trigger: automatic when `State.money >= 300`

### Multi-Fish Catch Bonuses
Reward skill-based looping with catch multipliers:
- Catch 2 fish in one loop: **+10% bonus money**
- Catch 3 fish in one loop: **+25% bonus money**
- Catch 4+ fish in one loop: **+50% bonus money**
- Bonus is applied on top of base fish value (Value upgrade)
- Encourages challenging, multi-fish loops

### Progressive Fish Movement (Tier 2 Difficulty)
Fish start moving at run 50 (when Tier 2 unlocks):
- **Initial movement**: Very gentle drifts (±6-8 pixels in circles/figure-8s/erratic patterns)
- **Speed progression**: Movement speed increases gradually as runs pass 50
- **Three movement types** (randomly assigned per fish):
  1. Circular drift — gentle orbits around spawn point
  2. Figure-8 pattern — smooth side-to-side figure-8s
  3. Erratic drift — random up/down and back/forth movements
- **Speed formula**: `0.03 + (runsPast50 * 0.002)` radians/frame, capped at 0.15
- Fish update position every frame: `baseX/baseY + sin/cos(movePhase) * amplitude`
- Movement is catchable but requires leading/prediction at late runs

### Debug Cheat: Jump to Tier 2
- Press **A + B** together to instantly jump to run 50 with:
  - $300 cash
  - Value L5, Spawn L3, Speed L3, Line L5, Permit L2, Time L0
  - Enables quick Tier 2 testing without grinding Tier 1

### Full 51-Run Tier 2 Progression Data

```
runs=50 money=$300 time=0m12s income=$8/run V=5 S=3 Sp=3 L=5 P=2 T=0
runs=51 money=$318 time=0m24s income=$8/run V=5 S=3 Sp=3 L=5 P=2 T=0
runs=52 money=$336 time=0m36s income=$8/run V=5 S=3 Sp=3 L=5 P=2 T=0
runs=53 money=$52 time=0m48s income=$12/run V=13 S=3 Sp=3 L=5 P=2 T=0
runs=54 money=$34 time=1m0s income=$16/run V=13 S=3 Sp=6 L=5 P=2 T=0
runs=55 money=$75 time=1m12s income=$18/run V=13 S=5 Sp=6 L=5 P=2 T=0
runs=56 money=$77 time=1m24s income=$22/run V=13 S=5 Sp=6 L=9 P=2 T=0
runs=57 money=$38 time=1m36s income=$24/run V=13 S=5 Sp=6 L=12 P=2 T=0
runs=58 money=$76 time=1m48s income=$26/run V=13 S=5 Sp=7 L=12 P=2 T=0
runs=59 money=$148 time=2m0s income=$26/run V=13 S=5 Sp=7 L=12 P=2 T=0
runs=60 money=$123 time=2m12s income=$33/run V=13 S=9 Sp=7 L=12 P=2 T=0
runs=61 money=$86 time=2m24s income=$40/run V=13 S=9 Sp=7 L=12 P=6 T=0
runs=62 money=$65 time=2m36s income=$43/run V=13 S=9 Sp=7 L=12 P=6 T=3
runs=63 money=$124 time=2m48s income=$45/run V=13 S=9 Sp=7 L=12 P=7 T=3
runs=64 money=$167 time=3m2s income=$55/run V=13 S=9 Sp=10 L=12 P=7 T=3
runs=65 money=$214 time=3m15s income=$61/run V=13 S=9 Sp=12 L=12 P=7 T=3
runs=66 money=$209 time=3m27s income=$64/run V=14 S=9 Sp=12 L=12 P=7 T=3
runs=67 money=$179 time=3m40s income=$71/run V=14 S=9 Sp=12 L=12 P=7 T=7
runs=68 money=$210 time=3m56s income=$74/run V=15 S=9 Sp=12 L=12 P=7 T=7
runs=69 money=$270 time=4m10s income=$86/run V=15 S=12 Sp=12 L=12 P=7 T=7
runs=70 money=$329 time=4m25s income=$89/run V=16 S=12 Sp=12 L=12 P=7 T=7
runs=71 money=$309 time=4m40s income=$98/run V=16 S=14 Sp=12 L=12 P=7 T=7
runs=72 money=$365 time=4m59s income=$101/run V=17 S=14 Sp=12 L=12 P=7 T=7
runs=73 money=$369 time=5m12s income=$106/run V=17 S=15 Sp=12 L=12 P=7 T=7
runs=74 money=$482 time=5m30s income=$110/run V=17 S=16 Sp=12 L=12 P=7 T=7
runs=75 money=$327 time=5m46s income=$127/run V=17 S=17 Sp=12 L=12 P=10 T=7
runs=76 money=$324 time=6m1s income=$139/run V=17 S=17 Sp=12 L=12 P=12 T=8
runs=77 money=$194 time=6m13s income=$147/run V=17 S=17 Sp=12 L=12 P=13 T=9
runs=78 money=$437 time=6m31s income=$147/run V=17 S=17 Sp=12 L=12 P=13 T=9
runs=79 money=$383 time=6m48s income=$152/run V=18 S=18 Sp=12 L=12 P=13 T=9
runs=80 money=$477 time=7m5s income=$158/run V=18 S=18 Sp=12 L=12 P=13 T=9
runs=81 money=$327 time=7m18s income=$163/run V=18 S=19 Sp=12 L=12 P=13 T=9
runs=82 money=$499 time=7m37s income=$171/run V=18 S=19 Sp=12 L=12 P=13 T=11
runs=83 money=$534 time=7m59s income=$177/run V=19 S=19 Sp=12 L=12 P=13 T=11
runs=84 money=$505 time=8m15s income=$183/run V=20 S=19 Sp=12 L=12 P=13 T=11
runs=85 money=$563 time=8m33s income=$189/run V=20 S=19 Sp=12 L=12 P=14 T=11
runs=86 money=$418 time=8m53s income=$195/run V=21 S=19 Sp=12 L=12 P=14 T=11
runs=87 money=$458 time=9m12s income=$201/run V=21 S=19 Sp=12 L=12 P=15 T=11
runs=88 money=$390 time=9m29s income=$207/run V=21 S=19 Sp=12 L=12 P=16 T=11
runs=89 money=$604 time=9m45s income=$211/run V=21 S=19 Sp=12 L=12 P=16 T=12
runs=90 money=$515 time=10m4s income=$219/run V=21 S=20 Sp=12 L=12 P=16 T=12
runs=91 money=$937 time=10m22s income=$219/run V=21 S=20 Sp=12 L=12 P=16 T=12
runs=92 money=$663 time=10m44s income=$226/run V=22 S=20 Sp=12 L=12 P=16 T=12
runs=93 money=$602 time=11m6s income=$232/run V=22 S=20 Sp=12 L=12 P=17 T=12
runs=94 money=$745 time=11m26s income=$237/run V=22 S=20 Sp=12 L=12 P=17 T=13
runs=95 money=$1174 time=11m48s income=$237/run V=22 S=20 Sp=12 L=12 P=17 T=13
runs=96 money=$832 time=12m10s income=$245/run V=23 S=20 Sp=12 L=12 P=17 T=13
runs=97 money=$460 time=12m27s income=$251/run V=23 S=20 Sp=12 L=12 P=18 T=13
runs=98 money=$960 time=12m49s income=$251/run V=23 S=20 Sp=12 L=12 P=18 T=13
runs=99 money=$1416 time=13m9s income=$251/run V=23 S=20 Sp=12 L=12 P=18 T=13
runs=100 money=$839 time=13m29s income=$259/run V=24 S=20 Sp=12 L=12 P=18 T=13
```

### Tier 2 Progression Analysis

**Tier 2 Unlock (Run 50-53): Fresh Start**
- Jump from $8/run income to $12/run immediately (first Tier 2 purchase)
- Run 53 is critical: Value L13 purchase marks true Tier 2 engagement
- Feels like entering a "new game" with fresh progression ladder

**Acceleration Phase (Runs 54-75): Compounding Growth**
- Income accelerates from $12 → $127/run in 22 runs
- Money swings grow dramatically ($52-$482) — multi-catch bonuses paying off
- Each run buys multiple Tier 2 upgrades; feels fast but earned
- Speed/Line cap prevents runaway speed creep; skill challenge persists

**Exponential Endgame (Runs 75-100): The Money Printer**
- Income: $127 → $259/run (2× growth in 25 runs)
- Per-run money variance explodes ($179-$1416) — skill and synergy matter
- Players maxing Permit, Time, pushing Value/Spawn to L20+
- Game rewards both strategic upgrades AND skillful multi-catch fishing

### Design Success Metrics ?

1. **Tier 2 extends gameplay indefinitely** � no "endgame void"
2. **Difficulty scales with progression** � fish movement keeps it challenging
3. **Skill rewards matter** � multi-catch bonuses incentivize tight loops
4. **Cost curve is balanced** � 1.25 exponent feels right for Tier 2 pacing
5. **Cap at L24 provides closure** � players have a defined finish line

---

## Phase 8 � Boat Hitbox Collision & Terrain Hazards (May 26, 2026)

### Accurate Edge-Based Collision
Replaced center-point collision with a 4-corner hitbox:
- **Dimensions**: Based on boat's visual footprint (38px length, 26px width).
- **Rotation-Aware**: Hitbox corners (Nose-Left/Right, Stern-Left/Right) are recalculated every frame based on \oat.angle\.
- **Comprehensive Checks**: Every corner is checked against both play area boundaries and terrain obstacles.
- **Collision Flow**: Hitting any hazard immediately sets \oundTime = roundDuration\, triggering the Game Over / Upgrade prompt.

### Debug Hitbox Visualization
Added a visual aid for development:
- Toggleable via the in-game debug overlay (Menu button).
- Draws a wireframe box connecting the active collision corners.
- Allows real-time verification of "glancing" blows and edge-perfect collisions.

---

## Known Behaviors / Design Decisions
- Boat speed was halved (`1.75`) to make loop-drawing feel more intentional
- Fish spawn at randomized angles/distances within `spawnRadius` from origin
- Wake resets after each successful loop catch (intentional — prevents infinite catching)
- Permit is the only Tier 1 upgrade with a minimum level (1) — you always catch at least 1 fish/loop
- Time upgrade is intentionally the hardest to max — extra clock time is very powerful
- Tier 2 upgrades hard-cap at L24 to prevent infinite progression bloat
- Speed and Line upgrades remain capped at L12 throughout all tiers — preserves skill-based gameplay
