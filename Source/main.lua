import "CoreLibs/graphics"
import "CoreLibs/sprites"

import "config"
import "state"
import "input"
import "physics"
import "entities"
import "ui"
import "telemetry"

gfx = playdate.graphics
geometry = playdate.geometry
math.randomseed(playdate.getSecondsSinceEpoch())

-- ---------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------

-- ---------------------------------------------------------
-- Game State
-- ---------------------------------------------------------

-- ---------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------
playdate.display.setRefreshRate(Config.RefreshRate)

-- Load level assets
local levelTopImage = gfx.image.new('images/level/2-top')
levelCollisionImage = gfx.image.new('images/level/2-collision')



littleguymenubImage = gfx.image.new('images/fish/littleguymenub')
dockSpriteImage = gfx.image.new('images/menu/dock_sprite')
playSpriteImage = gfx.image.new('images/menu/play_sprite')
upgradeSpriteImage = gfx.image.new('images/menu/upgrade_sprite')
dockObjectImage = gfx.image.new('images/fish/littleguy')
tapeImage = gfx.image.new('images/menu/tape_invert')
textboxImage = gfx.image.new('images/menu/textbox')

-- Load boat sprite (40x40 single image)
local boatImage = gfx.image.new('images/boat/boat40x40')

-- Load fonts for UI
roobert24 = gfx.font.new('fonts/Roobert-24-Medium')
roobert11 = gfx.font.new('fonts/Roobert-11-Medium')

-- Cache for fish images
fishImageCache = {}

preRenderFishImages()

-- ---------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------

-- Top-down projection: world coords -> screen coords
local function project(wx, wy)
    local rx = wx - State.boat.x
    local ry = wy - State.boat.y
    return Config.Screen.cx + rx, Config.Screen.cy + ry
end

waveTableRaw = gfx.imagetable.new('images/water/wave', 15, 24)
waveFrameCount = waveTableRaw and waveTableRaw:getLength() or 0
waveTableScaled = {}
waveInstances = {}

preScaleWaves()

initWaves()

spawnFish()
initLittleGuy()
Telemetry.init()

-- ---------------------------------------------------------
-- Progression Formulas
-- ---------------------------------------------------------
local UPGRADE_BASE_PRICES = { 5, 5, 2, 18, 25, 25, 15, 50 }
-- Value=$5, Speed=$5, Line=$2, Boost=$18, Value2=$25, Speed2=$25, Line2=$15, Boost2=$50

-- ---------------------------------------------------------
-- Input & Logic
-- ---------------------------------------------------------

-- ---------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------

local function drawBoat(x, y, angle)
    -- Draw boat sprite (rotated programmatically)
    if boatImage then
        boatImage:drawRotated(x, y, angle)
    end
end

local function drawContent()
    local bx, by = State.boat.x, State.boat.y
    local time = State.totalFramesPlayed

    gfx.clear(gfx.kColorBlack)

    -- Set draw mode for high contrast
    local mainDrawMode = gfx.kDrawModeInverted
    local uiColor = gfx.kColorWhite

    -- Draw Wave Sprite Sheet Animations
    if waveTableScaled and waveFrameCount > 0 then
        gfx.setImageDrawMode(mainDrawMode)
        local animSpeed = State.waveAnimSpeed / 3
        for _, w in ipairs(waveInstances) do
            local dx = w.x - bx
            local dy = w.y - by
            if dx > -230 and dx < 230 and dy > -150 and dy < 150 then
                local wx, wy = 200 + dx, 120 + dy
                local speedDiv = w.speed * animSpeed
                local frame = ((math.floor(time / speedDiv) + w.frameOffset) % waveFrameCount) + 1
                local img = waveTableScaled[frame]
                if img then
                    local iw, ih = img:getSize()
                    img:draw(wx - iw/2, wy - ih/2)
                end
            end
        end
    end

    -- Draw level terrain visual
    if levelTopImage then
        local lx, ly = project(0, 0)
        local sx = math.max(0, -lx)
        local sy = math.max(0, -ly)
        local sw = math.min(400, 1400 - sx)
        local sh = math.min(240, 1400 - sy)
        local tx = math.max(0, lx)
        local ty = math.max(0, ly)
        
        gfx.setImageDrawMode(mainDrawMode)
        levelTopImage:draw(tx, ty, gfx.kImageUnflipped, sx, sy, sw, sh)
    end

    -- Draw play area boundary
    local x1, y1 = project(0, 0)
    local x2, y2 = project(Config.PlayArea.width, Config.PlayArea.height)
    gfx.setColor(uiColor)
    gfx.setLineWidth(3)
    gfx.drawRect(x1, y1, x2 - x1, y2 - y1)
    gfx.setLineWidth(2)

    -- Draw wake
    local wake = State.wake
    if #wake >= 1 then
        gfx.setColor(uiColor)
        local sx, sy = State.boat.sternX or bx, State.boat.sternY or by
        gfx.drawLine(200 + (sx - bx), 120 + (sy - by), 200 + (wake[1].wx - bx), 120 + (wake[1].wy - by))
        for i = 1, #wake - 1 do
            local p1 = wake[i]
            local p2 = wake[i + 1]
            gfx.drawLine(200 + (p1.wx - bx), 120 + (p1.wy - by), 200 + (p2.wx - bx), 120 + (p2.wy - by))
        end
    end

    -- Draw fish
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    for _, f in ipairs(State.fish) do
        if f.alive then
            local dx, dy = f.x - bx, f.y - by
            if dx > -220 and dx < 220 and dy > -140 and dy < 140 then
                local fx, fy = 200 + dx, 120 + dy
                drawWavyFish(fx, fy, f.size, f.angle or 0)
            end
        end
    end

    -- Draw dock object and boat
    gfx.setImageDrawMode(mainDrawMode)
    if dockObjectImage then
        local dx, dy = 200 + (State.littleguy.x - bx), 120 + (State.littleguy.y - by)
        if dx > -50 and dx < 450 and dy > -50 and dy < 290 then
            dockObjectImage:drawAnchored(dx, dy, 0.5, 0.5)
        end
    end

    if boatImage then
        boatImage:drawRotated(200, 120, State.boat.angle)
    end

    -- Draw indicators pointing to off-screen fish
    if State.showFishMarkers then
        drawOffScreenFishIndicators()
    end

    -- Money display
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawText("$" .. State.money, 4, 4)

    -- Boost Cooldown Indicator
    drawBoostIndicator()

    -- Floating catch text popups
    drawFloatingTexts()

    -- Pause message
    if State.isPaused then
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(60, 70, 280, 100)
        gfx.setColor(uiColor)
        gfx.drawRect(60, 70, 280, 100)
        
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.setFont(roobert24)
        gfx.drawText("DOCK!", 135, 80)
        gfx.setFont(roobert11)
        gfx.drawText("Go back to dock?", 150, 115)
        gfx.drawText("A: Yes (Dock)   B: No (Stay)", 115, 140)
        gfx.setFont(nil)
    end
end

-- Main Loop
-- ---------------------------------------------------------
function playdate.update()
    handleInput()
    Telemetry.update()

    if State.infiniteMoney then
        State.money = 99999
    end

    -- ---------------------------------------------------------
    -- 1. State Updates
    -- ---------------------------------------------------------
    if State.currentScreen == "game" then
        if not State.isPaused then
            updatePhysics()
            updateFishMovement()
            updateLittleGuyMovement()
            updateWaves()
            updateFloatingTexts()
            
            local time = State.totalFramesPlayed
            State.totalFramesPlayed = time + 1
        end
    end

    -- ---------------------------------------------------------
    -- 2. Drawing
    -- ---------------------------------------------------------
    if State.currentScreen == "game" then
        gfx.clear(gfx.kColorBlack)
        drawContent()
    elseif State.currentScreen == "dock" then
        drawDockScreen()
    elseif State.currentScreen == "upgrade" then
        drawUpgradeScreen()
    elseif State.currentScreen == "music" then
        drawMusicScreen()
    elseif State.currentScreen == "debug" then
        drawDebugMenu()
    elseif State.currentScreen == "secret_menu" then
        drawSecretMenu()
    else
        -- Fallback: unknown screen
        gfx.clear(gfx.kColorWhite)
        gfx.drawText("Error: Unknown Screen '" .. tostring(State.currentScreen) .. "'", 10, 100)
    end
end
function calculateUpgradeCost(upgradeIndex, internalLevel)
    local effectiveIndex = upgradeIndex
    local effectiveLevel = internalLevel
    
    if upgradeIndex > 4 then
        effectiveIndex = upgradeIndex - 4
        effectiveLevel = internalLevel + getMaxUpgradeLevel(effectiveIndex)
    end

    local basePrice = UPGRADE_BASE_PRICES[effectiveIndex]
    -- Row 1 upgrades use a 1.18 exponent, while Row 2 upgrades use a steeper 1.25 exponent
    -- to match the player's accelerated Level 2 income
    local exponent = upgradeIndex > 4 and 1.25 or 1.18
    return math.floor(basePrice * (exponent ^ effectiveLevel) + effectiveLevel)
end

function getActualBoostCooldown()
    return math.max(0, State.boostCooldownDuration - (getEffectiveUpgradeLevel(4) * 0.5))
end

function resetRound()
    State.hold = 0
    State.isPaused = false
    State.pausedByDock = false
    
    -- Recycle existing wake points into pool
    for _, p in ipairs(State.wake) do
        table.insert(State.wakePool, p)
    end
    State.wake = {}
    State.boat.wakeLength = 0
    
    -- Find a safe spawn point for the boat starting at 852, 1065
    local startX, startY = 852, 1065
    if isInAnyObstacle(startX, startY) then
        -- Spiral outward to find nearest water
        local found = false
        local step = 10
        local radius = step
        while not found and radius < 400 do
            for angle = 0, 2 * math.pi, math.pi / 8 do
                local tx = startX + math.cos(angle) * radius
                local ty = startY + math.sin(angle) * radius
                if not isInAnyObstacle(tx, ty) then
                    startX, startY = tx, ty
                    found = true
                    break
                end
            end
            radius = radius + step
        end
    end
    
    State.boat.x = startX
    State.boat.y = startY
    State.boat.angle = 0
    State.boat.moveAngle = 0
    State.boat.currentSpeed = 0
    State.boat.velocity_x = 0
    State.boat.velocity_y = 0
    State.boat.boostSpeed = 0
    State.boat.boostFrames = 0
    State.boat.boostCooldownFrames = 0
    State.totalRunsPlayed = State.totalRunsPlayed + 1
    spawnFish()
    initWaves()
    initLittleGuy()
    Telemetry.logDepartDock()
end

