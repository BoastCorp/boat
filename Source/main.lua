import "CoreLibs/graphics"
import "CoreLibs/sprites"

local gfx = playdate.graphics
local geometry = playdate.geometry
math.randomseed(playdate.getSecondsSinceEpoch())

-- ---------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------
local Config = {
    Screen = { cx = 200, cy = 120 },
    Boat = {
        baseSpeed = 1.75,
        minTurnSpeed = 1.5,
        driftWeight = 0.15,
        rotationSpeed = 5,
        size = { w = 60, l = 60 }
    },
    Fish = {
        count = 5,
        spawnRadius = 200,
        size = 4,
    },
    Catch = {
        closeThreshold = 8,
        minLoopLength = 15,
    },
    WakeMaxLength = 110,
    RefreshRate = 50,
}

-- ---------------------------------------------------------
-- Game State
-- ---------------------------------------------------------
local State = {
    boat = {
        x = 0,
        y = 0,
        angle = 0,
        moveAngle = 0,
        currentSpeed = 0,
        velocity_x = 0,  -- Momentum in world space
        velocity_y = 0,
    },
    wake = {},
    fish = {},
    money = 0,
    roundDuration = 600,  -- 50 FPS * 12 seconds = 600 frames
    roundTime = 0,
    isPaused = false,
    currentScreen = "game",  -- "game" or "upgrade"
    upgrades = {
        { name = "Value",  level = 0 },  -- [1] Fish value: +$1 per level, +10% income mult
        { name = "Spawn",  level = 0 },  -- [2] Extra fish: +10% per level
        { name = "Speed",  level = 0 },  -- [3] Boat speed: +15% per level
        { name = "Line",   level = 0 },  -- [4] Wake length: +10% per level, +6% income mult
        { name = "Permit", level = 1 },  -- [5] Max fish per loop (min 1), +5% income mult
        { name = "Time",   level = 0 },  -- [6] % chance to add 1s back per catch, +3% income mult
    },
    selectedUpgrade = 1,
    debugEnabled = false,
    debugSelectedUpgrade = 1,
    totalRunsPlayed = 0,
    totalFramesPlayed = 0,
}

-- ---------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------
playdate.display.setRefreshRate(Config.RefreshRate)

-- Load water assets (4 layers, same as Rowbot Rally)
local waterBg          = gfx.image.new('images/water/water_bg')
local causticsOverlay  = gfx.image.new('images/water/caustics_overlay')
local causticsTable    = gfx.imagetable.new('images/water/caustics')
local waterTable       = gfx.imagetable.new('images/water/water')
local waterFrameCount  = waterTable and waterTable:getLength() or 0
local waterFrameTime   = 0

-- Load boat sprite (360-degree directional sprite sheet from Rowbot Rally)
local boatSprites = gfx.imagetable.new('images/boat/Boat60')
local shadowSprites = gfx.imagetable.new('images/boat/Shadow60')

-- Load fish images
local fishImages = {
    gfx.image.new('images/fish/clownfish'),
    gfx.image.new('images/fish/stur'),
    gfx.image.new('images/fish/anchovy'),
}

-- Load fonts for UI
local roobert24 = gfx.font.new('fonts/Roobert-24-Medium')
local roobert11 = gfx.font.new('fonts/Roobert-11-Medium')

-- Spawn fish at static positions around origin
for i = 1, Config.Fish.count do
    local angle = (i / Config.Fish.count) * 2 * math.pi
    local dist = 40 + math.random() * Config.Fish.spawnRadius
    local randomFishType = math.random(1, #fishImages)
    State.fish[i] = {
        x = math.cos(angle) * dist,
        y = math.sin(angle) * dist,
        alive = true,
        image = fishImages[randomFishType],
    }
end

-- ---------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------

-- Top-down projection: world coords -> screen coords
local function project(wx, wy)
    local rx = wx - State.boat.x
    local ry = wy - State.boat.y
    return Config.Screen.cx + rx, Config.Screen.cy + ry
end

-- Ray-casting point-in-polygon. poly is a list of tables with .wx/.wy fields.
local function pointInPolygon(px, py, poly)
    local inside = false
    local n = #poly
    local j = n
    for i = 1, n do
        local xi, yi = poly[i].wx, poly[i].wy
        local xj, yj = poly[j].wx, poly[j].wy
        if ((yi > py) ~= (yj > py)) and
           (px < (xj - xi) * (py - yi) / (yj - yi + 1e-10) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- ---------------------------------------------------------
-- Progression Formulas
-- ---------------------------------------------------------
local UPGRADE_BASE_PRICES = { 5, 6, 5, 2, 12, 18 }
-- Value=$5, Spawn=$6, Speed=$5, Line=$2, Permit=$12, Time=$18

local function calculateUpgradeCost(upgradeIndex, level)
    local basePrice = UPGRADE_BASE_PRICES[upgradeIndex]
    -- Tier 1: levels 1-12 use 1.18 exponent
    -- Tier 2: levels 13+ use 1.25 exponent (steeper cost curve)
    local exponent = level <= 12 and 1.18 or 1.25
    return math.floor(basePrice * (exponent ^ level) + level)
end

local function isTier2Unlocked()
    return State.money >= 300
end

local function calculateRunIncome()
    local income = 2  -- base $2/run (2 fish × $1 each)
    local mults = { 0.10, 0.10, 0.15, 0.06, 0.05, 0.03 }
    for i = 1, 6 do
        income = income * (1 + State.upgrades[i].level * mults[i])
    end
    return math.floor(income)
end

-- Helper to spawn fish respecting Spawn upgrade
local function spawnFish()
    local fishCount = math.floor(Config.Fish.count * (1 + State.upgrades[2].level * 0.1))
    State.fish = {}
    for i = 1, fishCount do
        local angle = (i / fishCount) * 2 * math.pi
        local dist = 40 + math.random() * Config.Fish.spawnRadius
        local randomFishType = math.random(1, #fishImages)
        local x = math.cos(angle) * dist
        local y = math.sin(angle) * dist
        State.fish[i] = {
            x = x,
            y = y,
            baseX = x,  -- base position for movement calculations
            baseY = y,
            alive = true,
            image = fishImages[randomFishType],
            movePhase = math.random() * 6.28,  -- random starting phase for movement
            moveType = math.random(1, 3),  -- 1=circle, 2=figure8, 3=erratic
        }
    end
end

-- Update fish positions based on movement phase
local function updateFishMovement()
    -- Fish start moving at run 50
    if State.totalRunsPlayed < 50 then
        return
    end

    -- Gentle movement: movement speed starts slow and increases with runs
    -- At run 50: move at ~0.03 radians/frame (about 20-30 pixels per second)
    local runsPast50 = math.max(0, State.totalRunsPlayed - 50)
    local movementSpeed = 0.03 + (runsPast50 * 0.002)  -- starts at 0.03, increases
    movementSpeed = math.min(movementSpeed, 0.15)  -- cap at 0.15 for late game

    for _, fish in ipairs(State.fish) do
        if fish.alive then
            -- Initialize movement fields if they don't exist (for pre-Tier 2 fish)
            if not fish.movePhase then
                fish.movePhase = math.random() * 6.28
                fish.moveType = math.random(1, 3)
                fish.baseX = fish.x
                fish.baseY = fish.y
            end

            fish.movePhase = fish.movePhase + movementSpeed

            if fish.moveType == 1 then
                -- Slow gentle drift: just small back and forth (±8 pixels max)
                fish.x = fish.baseX + math.sin(fish.movePhase) * 8
                fish.y = fish.baseY + math.cos(fish.movePhase) * 8
            elseif fish.moveType == 2 then
                -- Figure-8: small gentle pattern
                fish.x = fish.baseX + math.sin(fish.movePhase) * 6
                fish.y = fish.baseY + math.sin(fish.movePhase * 2) * 6
            else
                -- Random drift: very small movements
                fish.x = fish.baseX + math.sin(fish.movePhase) * 8
                fish.y = fish.baseY + math.cos(fish.movePhase * 1.5) * 8
            end
        end
    end
end

-- Helper to fully reset boat + round
local function resetRound()
    State.roundTime = 0
    State.isPaused = false
    State.wake = {}
    State.boat.x = 0
    State.boat.y = 0
    State.boat.angle = 0
    State.boat.moveAngle = 0
    State.boat.currentSpeed = 0
    State.boat.velocity_x = 0
    State.boat.velocity_y = 0
    State.totalRunsPlayed = State.totalRunsPlayed + 1
    spawnFish()
end

-- ---------------------------------------------------------
-- Input & Logic
-- ---------------------------------------------------------
local function updateInput()
    local boat = State.boat

    -- Crank steers the boat (visual angle)
    local crankChange = playdate.getCrankChange()
    boat.angle = boat.angle + crankChange

    -- Calculate angular delta: how misaligned are nose and movement directions?
    local angleDiff = math.abs((boat.angle - boat.moveAngle + 180) % 360 - 180)

    -- Apply speed penalty based on angular misalignment (cosine curve)
    -- 0° difference = 1.0 (full speed)
    -- 90° difference = 0.0 (clamped to 0.4 = 40% minimum speed)
    local cosAngleDiff = math.cos(math.rad(angleDiff))
    local dragFactor = math.max(0.4, cosAngleDiff)
    local speedMult = 1 + State.upgrades[3].level * 0.15
    boat.currentSpeed = Config.Boat.baseSpeed * speedMult * dragFactor

    -- Gradually align movement angle toward visual angle (drift)
    boat.moveAngle = boat.moveAngle + (boat.angle - boat.moveAngle) * Config.Boat.driftWeight

    -- Calculate velocity from movement angle at current speed
    local moveAngle_rad = math.rad(boat.moveAngle - 90)
    boat.velocity_x = math.cos(moveAngle_rad) * boat.currentSpeed
    boat.velocity_y = math.sin(moveAngle_rad) * boat.currentSpeed

    -- Apply velocity to position (top-down)
    boat.x = boat.x + boat.velocity_x
    boat.y = boat.y + boat.velocity_y

    -- Record stern position for wake trail
    local fwd_x = boat.velocity_x
    local fwd_y = boat.velocity_y
    local fwd_len = math.sqrt(fwd_x * fwd_x + fwd_y * fwd_y)
    if fwd_len > 0 then
        fwd_x = fwd_x / fwd_len
        fwd_y = fwd_y / fwd_len
    end

    local sternOffset = Config.Boat.size.l / 2 - 20
    local sternWx = boat.x - fwd_x * sternOffset
    local sternWy = boat.y - fwd_y * sternOffset
    local right_wx =  fwd_y
    local right_wy = -fwd_x

    local wake = State.wake

    -- Smooth new point toward previous to reduce jitter
    if #wake > 0 then
        local prev = wake[1]
        sternWx = sternWx * 0.6 + prev.wx * 0.4
        sternWy = sternWy * 0.6 + prev.wy * 0.4
    end

    table.insert(wake, 1, { wx = sternWx, wy = sternWy, rx = right_wx, ry = right_wy })
    local wakeMax = math.floor(Config.WakeMaxLength * (1 + State.upgrades[4].level * 0.1))
    if #wake > wakeMax then
        wake[#wake] = nil
    end

    -- Loop detection: if stern gets close to an older wake point, catch fish inside
    if #wake >= Config.Catch.minLoopLength then
        local head = wake[1]
        local threshSq = Config.Catch.closeThreshold * Config.Catch.closeThreshold
        for i = Config.Catch.minLoopLength, #wake do
            local p = wake[i]
            local ddx = head.wx - p.wx
            local ddy = head.wy - p.wy
            if ddx * ddx + ddy * ddy <= threshSq then
                -- Build polygon from the closed portion of the wake
                local poly = {}
                for j = 1, i do
                    poly[j] = wake[j]
                end
                -- Catch fish inside the polygon (capped by Permit level)
                local permitLimit = State.upgrades[5].level
                local caught = 0
                for _, f in ipairs(State.fish) do
                    if f.alive and pointInPolygon(f.x, f.y, poly) and caught < permitLimit then
                        f.alive = false
                        State.money = State.money + 1 + State.upgrades[1].level
                        caught = caught + 1
                        -- Time upgrade: 5% chance per level to add 1 second back
                        local timeChance = State.upgrades[6].level * 0.05
                        if math.random() < timeChance then
                            State.roundTime = math.max(0, State.roundTime - 50)
                        end
                    end
                end

                -- Multi-fish catch bonus
                local bonusMultiplier = 1.0
                if caught >= 2 then
                    bonusMultiplier = 1.1  -- +10% for 2 fish
                end
                if caught >= 3 then
                    bonusMultiplier = 1.25  -- +25% for 3 fish
                end
                if caught >= 4 then
                    bonusMultiplier = 1.5  -- +50% for 4+ fish
                end
                if caught > 0 and bonusMultiplier > 1.0 then
                    State.money = State.money + math.floor((caught * (1 + State.upgrades[1].level)) * (bonusMultiplier - 1))
                end
                -- Reset wake after catching
                State.wake = {}
                break
            end
        end
    end
end

-- ---------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------
local function drawOffScreenFishIndicators()
    -- Draw triangles pointing to off-screen fish
    local margin = 15
    gfx.setColor(gfx.kColorBlack)

    for _, f in ipairs(State.fish) do
        if f.alive then
            local fx = f.x - State.boat.x
            local fy = f.y - State.boat.y
            local sx = Config.Screen.cx + fx
            local sy = Config.Screen.cy + fy

            -- Check if fish is off-screen
            if sx < 0 or sx > 400 or sy < 0 or sy > 240 then
                -- Clamp position to screen edge with margin
                local clampedX = math.max(margin, math.min(400 - margin, sx))
                local clampedY = math.max(margin, math.min(240 - margin, sy))

                -- Calculate direction angle
                local dx = sx - 200
                local dy = sy - 120
                local angle = math.atan2(dy, dx)

                -- Draw small filled triangle pointing in the direction
                local size = 6
                local p1x = clampedX + math.cos(angle) * size
                local p1y = clampedY + math.sin(angle) * size
                local p2x = clampedX + math.cos(angle + 2.4) * size
                local p2y = clampedY + math.sin(angle + 2.4) * size
                local p3x = clampedX + math.cos(angle - 2.4) * size
                local p3y = clampedY + math.sin(angle - 2.4) * size

                gfx.fillPolygon(p1x, p1y, p2x, p2y, p3x, p3y)
            end
        end
    end
end

local function getSpriteFrame(angle)
    -- Normalize angle to 1-360 range and return frame index
    local normalized = angle % 360
    if normalized < 0 then
        normalized = normalized + 360
    end
    local frameIndex = math.floor(normalized + 0.5)
    if frameIndex == 0 then frameIndex = 360 end
    if frameIndex > 360 then frameIndex = 360 end
    return frameIndex
end

local function drawBoat(x, y, angle)
    -- Draw boat sprite anchored at center
    local frameIndex = getSpriteFrame(angle)

    -- Draw shadow sprite (offset by 5 pixels)
    if shadowSprites and shadowSprites[frameIndex] then
        shadowSprites[frameIndex]:drawAnchored(x + 5, y + 5, 0.5, 0.5)
    end

    -- Draw boat sprite anchored at center
    if boatSprites and boatSprites[frameIndex] then
        boatSprites[frameIndex]:drawAnchored(x, y, 0.5, 0.5)
    end
end

local function drawContent()
    -- Water layers (matches Rowbot Rally order)
    local bx, by = State.boat.x, State.boat.y
    local frame = (math.floor(waterFrameTime / 11.72) % waterFrameCount) + 1

    -- 1. Static base
    if waterBg then waterBg:draw(0, 0) end

    -- 2. Animated caustics (slow pan, opposite to boat direction)
    if causticsTable then
        local img = causticsTable:getImage(frame)
        if img then
            local px = ((-math.floor(bx / 4) * 2) % 400) - 400
            local py = ((-math.floor(by / 4) * 2) % 240) - 240
            img:draw(px, py)
        end
    end

    -- 3. Caustics overlay (static, camera-locked)
    if causticsOverlay then causticsOverlay:draw(0, 0) end

    -- 4. Animated water (faster pan, opposite to boat direction)
    if waterTable then
        local img = waterTable:getImage(frame)
        if img then
            local px = ((-bx * 0.8) % 400) - 400
            local py = ((-by * 0.8) % 240) - 240
            img:draw(px, py)
        end
    end

    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)

    -- Draw wake as simple lines (fast, no polygon building)
    local wake = State.wake
    local wakeLen = #wake
    if wakeLen >= 2 then
        local step = 3  -- Sample every 3rd point to reduce draw calls
        for i = 1, wakeLen - 1, step do
            if wake[i + step] then
                local x1, y1 = project(wake[i].wx, wake[i].wy)
                local x2, y2 = project(wake[i + step].wx, wake[i + step].wy)
                gfx.drawLine(x1, y1, x2, y2)
            end
        end
    end

    -- Draw fish (stationary images)
    for _, f in ipairs(State.fish) do
        if f.alive and f.image then
            local fx, fy = project(f.x, f.y)
            f.image:drawAnchored(fx, fy, 0.5, 0.5)
        end
    end

    -- Draw boat (includes shadow with dithering) at screen center
    local boat_screen_x, boat_screen_y = project(State.boat.x, State.boat.y)
    drawBoat(boat_screen_x, boat_screen_y, State.boat.angle)

    -- Draw indicators pointing to off-screen fish
    drawOffScreenFishIndicators()

    -- Money display
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText("$" .. State.money, 4, 4)

    -- Timer (countdown from 12 to 0)
    local remainingSeconds = math.ceil((State.roundDuration - State.roundTime) / 50)
    if remainingSeconds < 0 then remainingSeconds = 0 end
    gfx.setFont(roobert24)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(remainingSeconds, 360, 4)
    gfx.setFont(nil)

    -- Pause message (displayed over the game)
    if State.isPaused then
        gfx.setColor(gfx.kColorBlack)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.setFont(roobert24)
        gfx.drawText("Press B to continue", 40, 80)
        gfx.drawText("or A to upgrade", 70, 120)
        gfx.setFont(nil)
    end

    -- Small debug panel (top-right, tiny font, toggle with Menu button)
    if State.debugEnabled then
        local v  = State.upgrades[1].level
        local s  = State.upgrades[2].level
        local sp = State.upgrades[3].level
        local l  = State.upgrades[4].level
        local p  = State.upgrades[5].level
        local t  = State.upgrades[6].level
        local income = calculateRunIncome()
        local nextV  = calculateUpgradeCost(1, v + 1)
        local nextS  = calculateUpgradeCost(2, s + 1)
        local nextSp = calculateUpgradeCost(3, sp + 1)

        -- White background box
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(220, 44, 178, 42)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(220, 44, 178, 42)

        gfx.setFont(nil)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.drawText("V:"..v.." S:"..s.." Sp:"..sp.." L:"..l.." P:"..p.." T:"..t, 224, 46)
        gfx.drawText("Income: $"..income.."/run", 224, 56)
        gfx.drawText("Next V=$"..nextV.." S=$"..nextS.." Sp=$"..nextSp, 224, 66)
        gfx.drawText("Runs:"..State.totalRunsPlayed.."  $"..State.money, 224, 76)
    end
end

-- ---------------------------------------------------------
-- Upgrade Screen
-- ---------------------------------------------------------
local function drawUpgradeScreen()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(roobert11)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Wallet header
    gfx.drawText("Wallet: $" .. State.money .. "   Income/run: $" .. calculateRunIncome(), 10, 8)

    -- Divider
    gfx.drawLine(0, 24, 400, 24)

    -- List of upgrades
    local listStartY = 36
    local rowHeight = 26
    for i, upgrade in ipairs(State.upgrades) do
        local y = listStartY + (i - 1) * rowHeight

        -- Highlight selected row
        if i == State.selectedUpgrade then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(0, y - 2, 400, rowHeight)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        -- Name on left
        gfx.drawText(upgrade.name, 20, y)

        -- Level in middle
        local levelStr = upgrade.level .. "/12"
        gfx.drawText(levelStr, 120, y)

        -- Cost to next level
        local maxLevel = (i == 3 or i == 4) and 12 or 24  -- Speed & Line capped at 12, others at 24
        if upgrade.level < maxLevel then
            local nextCost = calculateUpgradeCost(i, upgrade.level + 1)
            local canAfford = State.money >= nextCost
            local costStr = canAfford and ("$" .. nextCost) or ("$" .. nextCost .. " ?")
            gfx.drawText(costStr, 180, y)
        else
            gfx.drawText("MAX", 180, y)
        end

        -- Arrows and level on right (only on selected row)
        if i == State.selectedUpgrade then
            gfx.drawText("< >", 320, y)
        end
    end

    -- Bottom hint
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, 216, 400, 216)
    gfx.drawText("crank/up/down: select   A: buy   left: refund   B: continue", 10, 220)

    gfx.setFont(nil)
end

-- ---------------------------------------------------------
-- Debug Menu Screen
-- ---------------------------------------------------------
local function drawDebugMenu()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(roobert11)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Title
    gfx.drawText("* DEBUG MENU - PROGRESSION *", 90, 4)
    gfx.drawLine(0, 18, 400, 18)

    -- Upgrades list
    local upgradeMults = { 0.10, 0.10, 0.15, 0.06, 0.05, 0.03 }
    local y = 24
    for i = 1, 6 do
        local upgrade = State.upgrades[i]
        local nextCost = calculateUpgradeCost(i, upgrade.level + 1)
        local currentMult = 1 + (upgrade.level * upgradeMults[i])
        local maxLevel = (i == 3 or i == 4) and 12 or 24

        if i == State.debugSelectedUpgrade then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(0, y - 1, 400, 14)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        local levelStr = "L" .. upgrade.level
        local costStr  = upgrade.level < maxLevel and ("Next:$" .. nextCost) or "MAXED"
        local multStr  = string.format("x%.2f", currentMult)
        gfx.drawText(string.format("%-6s  %-6s  %-10s  %s", upgrade.name, levelStr, costStr, multStr), 8, y)

        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        y = y + 14
    end

    -- Divider
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, y + 2, 400, y + 2)
    y = y + 6

    -- Income breakdown
    gfx.drawText("INCOME BREAKDOWN:", 8, y)
    y = y + 12
    local runIncome = 2
    local multNames = {"Value", "Spawn", "Speed", "Line", "Permit", "Time"}
    local mults = { 0.10, 0.10, 0.15, 0.06, 0.05, 0.03 }
    gfx.drawText("Base: $2", 8, y)
    y = y + 10
    for i = 1, 6 do
        local prev = runIncome
        runIncome = runIncome * (1 + State.upgrades[i].level * mults[i])
        if State.upgrades[i].level > 0 then
            gfx.drawText(string.format("x %s L%d: $%d -> $%d", multNames[i], State.upgrades[i].level, math.floor(prev), math.floor(runIncome)), 8, y)
            y = y + 10
        end
    end
    gfx.drawLine(0, y + 1, 200, y + 1)
    y = y + 4
    gfx.drawText("TOTAL/RUN: $" .. math.floor(runIncome), 8, y)
    y = y + 12

    -- Stats
    gfx.drawText("Runs: " .. State.totalRunsPlayed .. "   Money: $" .. State.money, 8, y)
    y = y + 12

    -- Controls footer
    gfx.drawLine(0, 224, 400, 224)
    gfx.setFont(nil)  -- smallest font for controls
    gfx.drawText("U/D:select  L/R:level  A:buy  B:exit  Menu+A:+$500  Menu+B:reset", 4, 227)
end

-- ---------------------------------------------------------
-- Main Loop
-- ---------------------------------------------------------
function playdate.update()

    -- A + B pressed together = jump to Tier 2
    if playdate.buttonJustPressed(playdate.kButtonA) and playdate.buttonIsPressed(playdate.kButtonB) then
        -- Jump to Tier 2: set to run 50 with $300 and some Tier 1 upgrades
        State.totalRunsPlayed = 50
        State.money = 300
        State.upgrades[1].level = 5  -- Value L5
        State.upgrades[2].level = 3  -- Spawn L3
        State.upgrades[3].level = 3  -- Speed L3
        State.upgrades[4].level = 5  -- Line L5
        State.upgrades[5].level = 2  -- Permit L2
        State.upgrades[6].level = 0  -- Time L0
    end

    -- Menu button: toggle debug panel; Menu+A = debug screen; Menu+B = reset upgrades; Menu+Right = +$500
    if playdate.buttonJustPressed(playdate.kButtonMenu) then
        if playdate.buttonIsPressed(playdate.kButtonA) then
            State.currentScreen = "debug"
        elseif playdate.buttonIsPressed(playdate.kButtonB) then
            for i = 1, 6 do
                State.upgrades[i].level = (i == 5) and 1 or 0
            end
            State.money = 0
            State.totalRunsPlayed = 0
        elseif playdate.buttonIsPressed(playdate.kButtonRight) then
            State.money = State.money + 500
        else
            State.debugEnabled = not State.debugEnabled
        end
    end

    if State.currentScreen == "game" then
        -- Only update input and physics if not paused
        if not State.isPaused then
            updateInput()
            updateFishMovement()
            State.totalFramesPlayed = State.totalFramesPlayed + 1
        end

        -- Increment round time
        State.roundTime = State.roundTime + 1
        if State.roundTime >= State.roundDuration and not State.isPaused then
            State.isPaused = true
            -- Print progression snapshot to console
            local secs = math.floor(State.totalFramesPlayed / Config.RefreshRate)
            local mins = math.floor(secs / 60)
            local income = calculateRunIncome()
            local u = State.upgrades
            print("runs=" .. State.totalRunsPlayed ..
                  " money=$" .. State.money ..
                  " time=" .. mins .. "m" .. (secs % 60) .. "s" ..
                  " income=$" .. income .. "/run" ..
                  " V=" .. u[1].level ..
                  " S=" .. u[2].level ..
                  " Sp=" .. u[3].level ..
                  " L=" .. u[4].level ..
                  " P=" .. u[5].level ..
                  " T=" .. u[6].level)
        end

        -- Pause menu: B = new round, A = upgrade screen
        if State.isPaused then
            if playdate.buttonJustPressed(playdate.kButtonB) then
                resetRound()
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                State.currentScreen = "upgrade"
            end
        end

        waterFrameTime = waterFrameTime + 1
        gfx.clear()
        drawContent()

    elseif State.currentScreen == "upgrade" then
        -- Crank scrolls up/down through the list
        local crankChange = playdate.getCrankChange()
        if crankChange > 10 then
            State.selectedUpgrade = math.min(#State.upgrades, State.selectedUpgrade + 1)
        elseif crankChange < -10 then
            State.selectedUpgrade = math.max(1, State.selectedUpgrade - 1)
        end

        local sel = State.selectedUpgrade

        if playdate.buttonJustPressed(playdate.kButtonUp) then
            State.selectedUpgrade = math.max(1, sel - 1)
        end
        if playdate.buttonJustPressed(playdate.kButtonDown) then
            State.selectedUpgrade = math.min(#State.upgrades, sel + 1)
        end
        if playdate.buttonJustPressed(playdate.kButtonA) then
            -- A = buy next level
            local nextLevel = State.upgrades[sel].level + 1
            -- Speed (3) and Line (4) capped at 12; Value/Spawn/Permit/Time capped at 24
            local maxLevel = (sel == 3 or sel == 4) and 12 or 24
            if nextLevel <= maxLevel then
                local cost = calculateUpgradeCost(sel, nextLevel)
                if State.money >= cost then
                    State.money = State.money - cost
                    State.upgrades[sel].level = nextLevel
                end
            end
        end
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            -- Left = refund one level
            local minLevel = (sel == 5) and 1 or 0
            if State.upgrades[sel].level > minLevel then
                local refund = calculateUpgradeCost(sel, State.upgrades[sel].level)
                State.money = State.money + refund
                State.upgrades[sel].level = State.upgrades[sel].level - 1
            end
        end
        if playdate.buttonJustPressed(playdate.kButtonB) then
            State.currentScreen = "game"
            resetRound()
        end

        drawUpgradeScreen()

    elseif State.currentScreen == "debug" then
        -- Debug menu: up/down select, left/right set level directly (free, no cost)
        local sel = State.debugSelectedUpgrade
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            State.debugSelectedUpgrade = math.max(1, sel - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            State.debugSelectedUpgrade = math.min(6, sel + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
            local minLevel = (sel == 5) and 1 or 0
            State.upgrades[sel].level = math.max(minLevel, State.upgrades[sel].level - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.upgrades[sel].level = math.min(12, State.upgrades[sel].level + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- Buy next level at proper cost
            local nextLevel = State.upgrades[sel].level + 1
            if nextLevel <= 12 then
                local cost = calculateUpgradeCost(sel, nextLevel)
                if State.money >= cost then
                    State.money = State.money - cost
                    State.upgrades[sel].level = nextLevel
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonMenu) then
            if playdate.buttonIsPressed(playdate.kButtonA) then
                State.money = State.money + 500
            elseif playdate.buttonIsPressed(playdate.kButtonB) then
                for i = 1, 6 do
                    State.upgrades[i].level = (i == 5) and 1 or 0
                end
                State.money = 0
                State.totalRunsPlayed = 0
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            State.currentScreen = "game"
        end

        drawDebugMenu()
    end
end
