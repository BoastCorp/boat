# Game Design Document: Boat Game (Working Title: Loop)

**Platform:** Playdate (1-bit, High-Contrast Screen, Crank Mechanics)
**Genre:** Arcade Incremental Fishing Game

## 1. Core Gameplay Loop
The player operates a fishing boat in a top-down perspective, navigating water to catch fish. The game focuses on a tight, satisfying loop of catching and selling.

*   **Catching:** Fish are caught by closing a "wake loop" (drawing a circle with the boat's trail) around them.
*   **Hold Capacity:** The boat has a limited capacity. Every fish caught takes up 1 slot.
*   **The Run:** A run ends when the boat's hold is full. The player then returns to the dock.
*   **Upgrading:** Money earned from catches is spent on 4 core stats to improve efficiency.

## 2. Progression System (The 4 Core Stats)
Consolidated from the original design to focus on the most impactful mechanics:

| Stat | Flavor Name | Description | Progression |
| :--- | :--- | :--- | :--- |
| **Value** | **Market Insight** | Dollars earned per fish caught. | +$1 per level. |
| **Speed** | **Turbo Motor** | Maximum engine power and acceleration. | +15% per level (Capped at L12). |
| **Line** | **Nylon Braided Wake** | Persistence/Length of the wake trail. | +10% per level (Capped at L12). |
| **Capacity** | **Hold Expansion** | Number of slots in the loot hold. | +3 slots per level. |

## 3. Movement & Physics
*   **Angular Drag:** Visual angle (Crank) controls the boat's nose, while movement angle lags behind, simulating drift and momentum.
*   **Reflective Bounce:** Terrain and boundaries are non-lethal. Hitting them results in a physical, decaying bounce-back (Soccer ball style).

## 4. Visual Style & Aesthetic
*   **High-Contrast 1-Bit:** Utilizing Playdate's unique screen for crisp, clean sprites.
*   **Animated Environment:** Multi-layered water caustics and smooth sprite rotation (360 frames).

---
**Note:** This document is iterative. Focus is currently on the core arcade loop and Zone 1 polish. Always confirm if these goals still reflect the current vision before major implementations.
