# Boat Game Development Progress

## Overview
This document summarizes all development work done on the Playdate boat fishing game, including physics implementation, sprite updates, and visual improvements.

## Major Accomplishments

### 1. Fish Sprite Replacement (Early Session)
- **Task**: Replace circular dots representing fish with PNG sprites
- **Implementation**: 
  - Added three fish PNG images: clownfish, stur, and anchovy
  - Created randomized spawning system that assigns a random fish type to each spawned fish
  - Replaced circle drawing with image drawing using `drawAnchored()`
- **Result**: Fish now appear as varied PNG sprites instead of plain circles, adding visual interest

### 2. Physics System Overhaul: From Momentum to Angular Drag

#### Initial Arcade Physics Attempt
- First explored using pure arcade-style constant velocity steering (removing all momentum)
- Increased boat speed from 2.0 to 3.5 px/frame for arcade feel
- Found this lacked the "weight" and feedback of Star Sled

#### Angular Drag Implementation (Final)
- **Concept**: Implemented physics based on Star Sled's mechanics where boat slows down during sharp turns due to misalignment between visual angle (nose direction) and movement angle (velocity direction)
- **Key Parameters Added to Config**:
  - `baseSpeed = 3.5` - Target forward speed
  - `minTurnSpeed = 1.5` - Minimum speed during sharp turns (clamped to 0.4 multiplier)
  - `driftWeight = 0.15` - How fast movement angle catches up to visual angle
- **Key State Variables Added**:
  - `moveAngle` - Direction velocity actually points (lags behind visual angle)
  - `currentSpeed` - Speed after drag penalty applied
- **Physics Logic**:
  1. Crank directly controls visual angle (instant response)
  2. Calculate angular delta between nose and movement direction
  3. Apply cosine-based speed penalty: `speed = baseSpeed * max(0.4, cos(angleDiff))`
     - 0° difference = full speed
     - 90° difference = 40% speed (feels like lateral resistance)
  4. Gradually drift movement angle toward visual angle for smooth recovery
  5. Calculate velocity from movement angle at current speed
- **Result**: Game feels arcade-responsive with tactile weight on sharp turns, matching Star Sled's feel

### 3. Wake Trail Visual Improvements

#### Wake Line Thickness
- Increased wake line width from 1 pixel to 2 pixels using `gfx.setLineWidth(2)`
- Makes the wake trail more visible and prominent

#### Wake Attachment to Boat
- Modified stern offset calculation from `Config.Boat.size.l / 2` to `Config.Boat.size.l / 2 - 20`
- This brings the wake start point closer to the boat, making it appear to originate from underneath the sprite
- Creates better visual connection between boat and wake trail

### 4. Sprite Management

#### Initial Boat Sprite Work
- Explored different sprite formats from Rowbot Rally
- Tested programmatic rotation (didn't match pre-rendered quality)
- Ultimately kept 360-frame sprite sheets as superior quality

#### Sprite Scaling with Aseprite
- Created scaled-down boat versions using Aseprite's Image → Scale Image feature
- Generated multiple sizes:
  - Boat40 (40x40 pixels)
  - Boat60 (60x60 pixels)
  - Original boat (80x80 pixels)
- Also scaled shadow sprites to match

#### Final Sprite Configuration
- **Currently Using**: Boat60 and Shadow60 (60x60 pixels)
- Shadow offset: 5 pixels from boat center
- All sprites remain as GIF imagetables with 360 rotational frames

## Current Game Configuration

```lua
Config.Boat = {
    baseSpeed = 3.5,
    minTurnSpeed = 1.5,
    driftWeight = 0.15,
    rotationSpeed = 5,
    size = { w = 60, l = 60 }
}
```

## Files Modified
- **Source/main.lua**:
  - Updated Config with angular drag parameters
  - Added moveAngle and currentSpeed to boat state
  - Replaced momentum lerping with angular drag physics
  - Increased wake line width to 2 pixels
  - Modified stern offset for wake attachment
  - Updated sprite loading to use Boat60 and Shadow60
  - Changed shadow offset from 7 to 5 pixels

- **Source/images/fish/**:
  - Added clownfish.png, stur.png, anchovy.png

- **Source/images/boat/**:
  - Added boat60.gif (60x60 scaled version)
  - Added shadow60.gif (60x60 scaled version)
  - Kept original boat.gif and shadow.gif for reference

## Physics Deep Dive: Why Angular Drag Works

The angular drag system is superior to simple momentum because:

1. **Self-Explanatory**: Players can visually see the nose leading the movement, making the slowdown intuitive
2. **Arcade Responsive**: No sluggish momentum accumulation; crank changes angle instantly
3. **Tactile Feedback**: Sharp 90° turns feel impactful with visible slowdown; gentle curves feel smooth
4. **Physics-Based**: Uses real angular misalignment as the cause of slowdown, not arbitrary magic numbers
5. **Auto-Recovery**: As drift brings movement angle toward visual angle, speed automatically recovers

## Testing Notes
- Sharp turns: Visual angle jumps instantly, movement angle lags behind, creating slowdown effect
- Gentle curves: Minimal angle difference, minimal slowdown, smooth sailing
- Straight lines: Angles aligned, full speed maintained
- Fish catching: Wake loop detection continues to work correctly with new physics

## Next Steps (Optional)
- Experiment with driftWeight values (0.05–0.25) to adjust how "sticky" the movement feels
- Consider adding crank indicator for player feedback
- Test edge wrapping (Asteroids-style) vs. camera following
- Further tune baseSpeed if game feels too slow/fast

## Git Commits
1. "Replace fish dots with randomized PNG sprites"
2. "Implement Angular Drag physics for arcade-style steering"
3. "Switch to Boat60 and Shadow60 sprites with adjusted shadow offset"
