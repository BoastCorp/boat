# Game Design Document: Project "Digital Drift" (Working Title)

**Platform:** Playdate (1-bit, High-Contrast Screen, Crank Mechanics)
**Genre:** Surrealist Incremental Fishing Game

## 1. The Core Loop ("The Run")
The game thrives on a rapid, satisfying, 3-step physical loop that forces the player back to base naturally, keeping sessions snappy.

`[ THE DOCK ] ──► [ SAIL OUT ] ──► [ LOOT HOLD FULL ] ──► [ RETURN TO DOCK ]`
`     ▲                                                               │`
`     └─────────── [ SELL TRASH & REVIEW MEDIA ] ◄────────────────────┘`

### Step 1: Setting Sail
The player departs the Dock with an empty Loot Hold (starting at 0/5 slots filled). They steer using the D-pad and trail their fishing line behind the boat.

### Step 2: The Hook & The Choice
The player steers over moving "dark spots" in the water, circling them precisely to close their boat's wake loop. Once closed, they use the Playdate hand crank to reel up the item.
**Tactile Feedback:** The screen shakes or briefly inverts colors (Black to White) on a successful catch to simulate physical impact without a rumble motor.

### Step 3: Max Capacity
Every item (Trash, Audio Tape, or VHS) occupies 1 slot. The moment the hold hits maximum capacity, the line automatically reels in and the console flashes: **HOLD FULL. RETURN TO DOCK.** The player can no longer cast their line and must head back to transition to the Hub.

---

## 2. Narrative Framework & The Endgame
**The Vibe:** Cult-classic indie surrealism. Deadpan humor that treats absolute internet absurdity with serious sci-fi framing.

**The "Why":** The player is an engineer searching a flooded tech-waste dumping ground for old components to build a scrap computer at their dock.

**The Hook:** While searching for computer parts, the player randomly dredges up audio tapes from real indie bands and personal cellphone/VHS footage of a chaotic TikTok creator ranting about her disastrous dating life and joking about "quantum jumping" to escape bad men.

**The Twist:** The player stops caring about building the computer for survival; they get hopelessly sucked into her parasocial dating drama.

**The Endgame Climax:** The player finally hoards enough late-game cash to buy the ultimate computer upgrade—the "Quantum Processor Core." When installed, the completed computer tracks her old digital signal and reveals the ultimate punchline: Her goofy manifestation actually worked. She successfully quantum leaped out of this reality. The machine processes her final message and locks onto coordinates in a parallel dimension.

---

## 3. Progression & Economy Matrix
Progression is strictly gated by physical overworld levels, which are unlocked by purchasing upgrading software patches on the dock computer. Finding story tapes is entirely random within these zones.

| Level / Zone | Upgrade Required to Open | Trash Value | Music Reward | TikTok Story Phase |
| :--- | :--- | :--- | :--- | :--- |
| **1. The Flooded Shallows** | None (Base Boat) | Low-Value (2–5 CC) | Unlocks early garage rock tracks | **The Honeymoon Phase** (Optimistic, funny rants about meeting a new guy). |
| **2. The Sunken Arcade** | Sonar Matrix v2.0 (Cost: 75 CC) | Mid-Value (10–25 CC) | Unlocks synth/experimental tracks | **The Red Flag Phase** (Absurd dating critiques, weird habits like eating kiwi skin). |
| **3. The Corporate Abyss** | Sonar Matrix v3.0 (Cost: 500 CC) | High-Value (75–150 CC) | Unlocks deep-cut tracks | **The Fallout Phase** (The toxic breakup, ghosting, and dumping her ex's gear in the lake). |

---

## 4. Complete Level Breakdown & Upgrade Tables

### Zone 1: The Flooded Shallows (Economy Setup)
**Environment:** Calm, clear waters filled with flooded telephone poles, rooftops, and basic suburban tech debris.
**Average Junk Sell Value:** 2–5 Data Credits (CC)
**Story Narrative:** The Honeymoon Phase.

| Category | Upgrade Name | Cost | Mechanical Effect |
| :--- | :--- | :--- | :--- |
| Boat | Nylon Braided Wake | 15 CC | **Wake Persistence +25%**: Your line path stays on screen longer, making it easier to close loop circles. |
| Boat | 5HP Outboard Motor | 25 CC | **Boat Speed +20%**: Move across the water faster to hit more dark spots per run. |
| Boat | Canvas Duffel Rig | 30 CC | **Loot Capacity +3**: Increases your item hold from 5 slots to 8 slots before you have to return to dock. |
| Computer | Sonar Matrix v2.0 | 75 CC | **Unlocks Zone 2 (The Sunken Arcade)**: Triangulates the phone signal from the girl's Shallows videos to pin the next location on your Overworld Map. |

### Zone 2: The Sunken Arcade (Mid-Game Grind)
**Environment:** Corrupt data-streams meet neon aesthetics. Underwater whirlpools and shifting currents push the boat around, requiring precise steering to close loops.
**Average Junk Sell Value:** 10–25 Data Credits (CC)
**Story Narrative:** The Red Flag Phase.

| Category | Upgrade Name | Cost | Mechanical Effect |
| :--- | :--- | :--- | :--- |
| Boat | Lead-Weighted Line | 100 CC | **Sink Speed +30%**: The line drops to the target depth faster when you turn the Playdate crank. |
| Boat | 15HP Twin Motor | 175 CC | **Boat Speed +40%**: Crucial for fighting the underwater currents and whirlpools in the Arcade zone. |
| Boat | Reinforced Hull Winch | 200 CC | **Object Tearing**: Allows you to hook heavy debris (like collapsed signboards) and crank them out of the way to find hidden spots. |
| Base | Refurbished Tape Deck | 250 CC | **In-Boat Music Player**: Unlocks the audio menu inside the boat. You can now change unlocked band tracks live while fishing. |
| Computer | Sonar Matrix v3.0 | 500 CC | **Unlocks Zone 3 (The Corporate Abyss)**: Decodes the background data from her Arcade videos to map the deepest trench coordinates. |

### Zone 3: The Corporate Abyss (End-Game / Finale)
**Environment:** Total, crushing darkness. Submerged server farms and corporate high-rises. The player cannot see moving dark spots unless they are within the boat's headlight cone.
**Average Junk Sell Value:** 75–150 Data Credits (CC)
**Story Narrative:** The Fallout Phase.

| Category | Upgrade Name | Cost | Mechanical Effect |
| :--- | :--- | :--- | :--- |
| Boat | Polyethylene Hull Coating | 600 CC | **Current Immunity**: Completely stabilizes the boat against harsh water drift, letting you circle spots with perfect precision. |
| Boat | High-Cap Cargo Crate | 800 CC | **Loot Capacity Max**: Expands item hold to 25 slots, allowing massive, high-value farming runs. |
| Boat | Halogen Floodlight | 1,000 CC | **Abyss Visibility**: Doubles your view radius in the pitch-black water of the deep trench. |
| Computer | Quantum Processor Core | 2,500 CC | **Trigger Endgame**: The ultimate computer upgrade. Instantly decodes her final lost files and tracks her reality-jumping signal to finish the story. |
