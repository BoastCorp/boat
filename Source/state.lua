-- ---------------------------------------------------------
-- Game State Definition
-- ---------------------------------------------------------
State = {
    boat = {
        x = 852,  -- Start at 852, 1065
        y = 1065,
        sternX = 852,
        sternY = 1065,
        angle = 0,
        moveAngle = 0,
        currentSpeed = 0,
        velocity_x = 0,  -- Momentum in world space
        velocity_y = 0,
        bounceSpeed = 0,  -- New: persistent bounce momentum
        bounceFrames = 0, -- New: duration of bounce override
        boostSpeed = 0,   -- Arcade boost
        boostFrames = 0,
        boostCooldownFrames = 0,
    },
    littleguy = {
        x = 0,
        y = 0,
        angle = 0,
        targetAngle = 0,
        speed = 0.3,
        timer = 0,
        state = "drift",
        radius = 25, -- Collision radius
    },
    wake = {},
    wakePool = {}, -- Pre-allocated/recycled tables for wake points
    fish = {},
    money = 0,
    hold = 0,
    isPaused = false,
    pausedByDock = false,
    currentScreen = "game",  -- "game" or "upgrade"
    currentLevel = 1,
    upgrades = {
        { name = "Value",    level = 0 },  -- [1] Fish value: +$1 per level
        { name = "Speed",    level = 0 },  -- [2] Boat speed: +15% per level
        { name = "Line",     level = 0 },  -- [3] Wake length: +20% per level
        { name = "Boost",    level = 0 },  -- [4] Boost cooldown: -0.5s per level
    },
    selectedUpgrade = 1,
    selectedMusic = 1,          -- Currently active track
    musicSelectionIndex = 1,    -- Cursor position in music menu
    debugEnabled = false,
    debugSelectedUpgrade = 1,
    -- Secret Menu State
    secretMenuIndex = 1,
    boostCooldownDuration = 3.0,
    fishSizes = { 10, 20, 30, 40, 50, 60, 70, 80 },
    -- Wave Settings
    waveScale = 0.3,
    waveAnimSpeed = 1,
    waveCount = 110,
    -- Fish & Visuals
    fishCount = 15,
    fishSpeedMult = 1.0,
    showFishMarkers = true,
    totalRunsPlayed = 0,
    totalFramesPlayed = 0,
    floatingTexts = {},
    infiniteMoney = false,
}

function getEffectiveUpgradeLevel(baseIndex)
    return State.upgrades[baseIndex].level
end

function getMaxUpgradeLevel(index)
    if index == 4 then
        return 3
    else
        return 10
    end
end
