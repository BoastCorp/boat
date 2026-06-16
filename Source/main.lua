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
        size = { w = 40, l = 40 },
        radius = 20,
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
    PlayArea = {
        width = 1400,
        height = 1400,
    },
    Obstacles = {},
    WakeMaxLength = 190,
    RefreshRate = 50,
}

-- ---------------------------------------------------------
-- Game State
-- ---------------------------------------------------------
local State = {
    boat = {
        x = 852,  -- Start at 852, 1065
        y = 1065,
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
    upgrades = {
        { name = "Value",    level = 0 },  -- [1] Fish value: +$1 per level
        { name = "Speed",    level = 0 },  -- [2] Boat speed: +15% per level
        { name = "Line",     level = 0 },  -- [3] Wake length: +10% per level
    },
    selectedUpgrade = 1,
    selectedMusic = 1,          -- Currently active track
    musicSelectionIndex = 1,    -- Cursor position in music menu
    debugEnabled = false,
    debugSelectedUpgrade = 1,
    -- Secret Menu State
    secretMenuIndex = 1,
    boostCooldownDuration = 3.0,
    fishSizes = { 10, 20, 30, 40 },
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
}

-- ---------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------
playdate.display.setRefreshRate(Config.RefreshRate)

-- Load level assets
local levelTopImage = gfx.image.new('images/level/2-top')
local levelCollisionImage = gfx.image.new('images/level/2-collision')
local dockImage = gfx.image.new('images/level/dock-splash')
local dockObjectImage = gfx.image.new('images/fish/littleguy')
local tapeImage = gfx.image.new('images/menu/tape')

-- Load boat sprite (40x40 single image)
local boatImage = gfx.image.new('images/boat/boat40x40')

-- Load fonts for UI
local roobert24 = gfx.font.new('fonts/Roobert-24-Medium')
local roobert11 = gfx.font.new('fonts/Roobert-11-Medium')

-- Cache for fish images
local fishImageCache = {}

local function preRenderFishImages()
    for _, size in ipairs(State.fishSizes) do
        local w = math.ceil(size * 1.5) + 4
        local h = math.ceil(size * 0.7) + 4
        local img = gfx.image.new(w, h, gfx.kColorClear)
        
        gfx.pushContext(img)
            gfx.setColor(gfx.kColorWhite)
            gfx.fillEllipseInRect(2, 2, w-4, h-4)
        gfx.popContext()
        
        fishImageCache[size] = img
    end
end

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

-- Check if a point is inside a box (obstacle collision helper)
local function isPointInBox(px, py, box)
    return px >= box.x and px <= box.x + box.w and
           py >= box.y and py <= box.y + box.h
end

-- Check if fish is inside any obstacle (using collision mask)
local function isInAnyObstacle(x, y)
    if levelCollisionImage then
        -- In Playdate, sample returns a color. 
        -- If it's a 1-bit collision map, land is usually black (kColorBlack).
        local color = levelCollisionImage:sample(x, y)
        return color == gfx.kColorBlack
    end
    return false
end

-- Check if a coordinate is "Safe Water" (distance away from land and world edges)
local function isSafeWater(x, y, radius)
    local playArea = Config.PlayArea
    local r = radius or 0
    
    -- Check world boundaries
    if x < r or x > playArea.width - r or y < r or y > playArea.height - r then
        return false
    end

    -- Check center for land
    if isInAnyObstacle(x, y) then return false end
    
    -- If no radius check needed, we're done
    if r <= 0 then return true end
    
    -- Check 8 points around the circle to ensure clearance from land
    for a = 0, 7 do
        local angle = a * (math.pi / 4)
        local sx = x + math.cos(angle) * r
        local sy = y + math.sin(angle) * r
        if isInAnyObstacle(sx, sy) then return false end
    end
    
    return true
end

-- Helper to check if a new fish would overlap any existing fish
local function isOverlappingExistingFish(x, y, size)
    local padding = 10 -- pixels of extra space between edges as requested
    local w1 = size * 1.5
    local h1 = size * 0.7
    
    for i = 1, #State.fish do
        local other = State.fish[i]
        if other.alive then
            local w2 = other.size * 1.5
            local h2 = other.size * 0.7
            
            -- Efficient AABB overlap check with padding
            local dx = math.abs(x - other.x)
            local dy = math.abs(y - other.y)
            local min_dist_x = (w1 + w2) / 2 + padding
            local min_dist_y = (h1 + h2) / 2 + padding
            
            if dx < min_dist_x and dy < min_dist_y then
                return true
            end
        end
    end
    return false
end

-- Wave initialization logic
local waveTableRaw = gfx.imagetable.new('images/water/wave', 15, 24)
local waveFrameCount = waveTableRaw and waveTableRaw:getLength() or 0
local waveTableScaled = {}
local waveInstances = {}

local function preScaleWaves()
    if not waveTableRaw then return end
    waveTableScaled = {} -- Reset cache
    for i = 1, waveFrameCount do
        local img = waveTableRaw:getImage(i)
        local w, h = img:getSize()
        local sw, sh = math.floor(w * State.waveScale), math.floor(h * State.waveScale)
        if sw < 1 then sw = 1 end
        if sh < 1 then sh = 1 end
        local scaledImg = gfx.image.new(sw, sh)
        gfx.pushContext(scaledImg)
            img:drawScaled(0, 0, State.waveScale)
        gfx.popContext()
        waveTableScaled[i] = scaledImg
    end
end

preScaleWaves()

local function initWaves()
    waveInstances = {}
    local playArea = Config.PlayArea
    -- Scatter wave sprites based on secret menu count
    for i = 1, State.waveCount do
        local wx = math.random(0, playArea.width)
        local wy = math.random(0, playArea.height)
        
        -- Only place waves in water (not on land)
        if not isInAnyObstacle(wx, wy) then
            table.insert(waveInstances, {
                x = wx,
                y = wy,
                frameOffset = math.random(1, waveFrameCount),
                speed = math.random(2, 4) -- Base divisor for variety
            })
        end
    end
end

initWaves()

-- Procedural Wave Update logic
local function updateWaves()
    -- No state to update per-frame, handled in draw
end

-- Helper to spawn fish in Schools and Lone Scouts
local function spawnFish()
    local totalFish = State.fishCount
    State.fish = {}
    
    -- Playable area is 1000x1000 (visual 1400x1400)
    -- Center 1000x1000 means coords from 200 to 1200
    local minX, maxX = 200, 1200
    local minY, maxY = 200, 1200
    
    local fishPlaced = 0
    
    -- 1. Spawn Schools (Clusters)
    local numSchools = 3
    local fishPerSchool = 3
    
    for s = 1, numSchools do
        -- Find a safe Anchor Point (50px buffer from land/barriers)
        local anchorX, anchorY
        local attempts = 0
        repeat
            anchorX = math.random(minX, maxX)
            anchorY = math.random(minY, maxY)
            attempts = attempts + 1
        until isSafeWater(anchorX, anchorY, 50) or attempts > 100
        
        if attempts <= 100 then
            -- Spawn cluster around anchor
            for i = 1, fishPerSchool do
                local placedInCluster = false
                local clusterAttempts = 0
                while not placedInCluster and clusterAttempts < 20 do
                    local angle = math.random() * 2 * math.pi
                    local dist = math.random(15, 80) -- Increased range for better spacing
                    local fx = anchorX + math.cos(angle) * dist
                    local fy = anchorY + math.sin(angle) * dist
                    
                    local size = State.fishSizes[math.random(1, 4)]
                    
                    -- Ensure individual fish has 50px clearance from barriers and NOT overlapping existing fish
                    if isSafeWater(fx, fy, 50) and not isOverlappingExistingFish(fx, fy, size) then
                        fishPlaced = fishPlaced + 1
                        State.fish[fishPlaced] = {
                            x = fx, y = fy, baseX = fx, baseY = fy,
                            alive = true, size = size,
                            movePhase = math.random() * 6.28,
                            moveType = math.random(1, 3)
                        }
                        placedInCluster = true
                    end
                    clusterAttempts = clusterAttempts + 1
                end
            end
        end
    end
    
    -- 2. Spawn Lone Scouts (Fill remaining slots)
    local attempts = 0
    while fishPlaced < totalFish and attempts < 500 do
        local fx = math.random(minX, maxX)
        local fy = math.random(minY, maxY)
        
        -- Use 50px buffer as requested for all targets
        if isSafeWater(fx, fy, 50) then 
            local size = math.random(1, 5) == 5 and 40 or 20
            if not isOverlappingExistingFish(fx, fy, size) then
                fishPlaced = fishPlaced + 1
                State.fish[fishPlaced] = {
                    x = fx, y = fy, baseX = fx, baseY = fy,
                    alive = true, size = size,
                    movePhase = math.random() * 6.28,
                    moveType = math.random(1, 3)
                }
            end
        end
        attempts = attempts + 1
    end
    
    -- Fallback: If we couldn't place enough fish, try again with smaller radius
    if fishPlaced < totalFish then
        local attempts = 0
        while fishPlaced < totalFish and attempts < 500 do
            local fx = math.random(minX, maxX)
            local fy = math.random(minY, maxY)
            if isSafeWater(fx, fy, 30) then
                local size = math.random(1, 5) == 5 and 40 or 20
                if not isOverlappingExistingFish(fx, fy, size) then
                    fishPlaced = fishPlaced + 1
                    State.fish[fishPlaced] = {
                        x = fx, y = fy, baseX = fx, baseY = fy,
                        alive = true, size = size,
                        movePhase = math.random() * 6.28,
                        moveType = math.random(1, 3)
                    }
                end
            end
            attempts = attempts + 1
        end
    end
end

-- Helper to initialize littleguy in a safe water spot
local function initLittleGuy()
    local attempts = 0
    local minX, maxX = 200, 1200
    local minY, maxY = 200, 1200
    repeat
        State.littleguy.x = math.random(minX, maxX)
        State.littleguy.y = math.random(minY, maxY)
        attempts = attempts + 1
    until isSafeWater(State.littleguy.x, State.littleguy.y, 50) or attempts > 100
    
    State.littleguy.angle = math.random() * 360
    State.littleguy.targetAngle = State.littleguy.angle
    State.littleguy.timer = math.random(50, 150)
    State.littleguy.state = "drift"
end

-- Update littleguy movement (floating like a fish)
local function updateLittleGuyMovement()
    local lg = State.littleguy
    lg.timer = lg.timer - 1

    if lg.state == "drift" then
        lg.speed = 0.4
        local diff = (lg.targetAngle - lg.angle + 180) % 360 - 180
        lg.angle = lg.angle + diff * 0.05
        
        if lg.timer <= 0 then
            lg.state = "dart"
            lg.timer = math.random(20, 40)
            lg.targetAngle = lg.angle + math.random(-60, 60)
        end
    elseif lg.state == "dart" then
        lg.speed = 1.2
        local diff = (lg.targetAngle - lg.angle + 180) % 360 - 180
        lg.angle = lg.angle + diff * 0.1
        
        if lg.timer <= 0 then
            lg.state = "drift"
            lg.timer = math.random(60, 200)
        end
    end

    local rad = math.rad(lg.angle)
    local vx = math.cos(rad) * lg.speed
    local vy = math.sin(rad) * lg.speed
    
    local nx = lg.x + vx
    local ny = lg.y + vy

    -- Boundary check for littleguy
    if isInAnyObstacle(nx, ny) or nx < 100 or nx > 1300 or ny < 100 or ny > 1300 then
        lg.targetAngle = lg.angle + 180
        lg.state = "drift"
        lg.timer = 50
    else
        lg.x = nx
        lg.y = ny
    end
end

-- Call initial spawn
spawnFish()
initLittleGuy()

-- ---------------------------------------------------------
-- Progression Formulas
-- ---------------------------------------------------------
local UPGRADE_BASE_PRICES = { 5, 5, 2 }
-- Value=$5, Speed=$5, Line=$2

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
    -- Estimated income per full hold
    local fishValue = 1 + State.upgrades[1].level
    return math.floor(50 * fishValue) -- Simplified placeholder
end

-- Helper to fully reset boat + round
local function resetRound()
    State.hold = 0
    State.isPaused = false
    State.pausedByDock = false
    
    -- Recycle existing wake points into pool
    for _, p in ipairs(State.wake) do
        table.insert(State.wakePool, p)
    end
    State.wake = {}
    
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
end

-- Update fish positions based on movement phase
local function updateFishMovement()
    -- Gentle movement: movement speed starts slow and increases with runs
    local difficultyMult = (1.0 + (State.totalRunsPlayed * 0.05)) * State.fishSpeedMult
    difficultyMult = math.min(difficultyMult, 5.0) -- Cap difficulty

    for _, fish in ipairs(State.fish) do
        if fish.alive then
            -- Initialize state machine if not present
            if not fish.state then
                fish.state = "drift"
                fish.timer = math.random(50, 150)
                fish.angle = math.random() * 360
                fish.targetAngle = fish.angle
                fish.speed = 0.2
            end

            -- Update timer
            fish.timer = fish.timer - 1

            if fish.state == "drift" then
                -- Slow gentle drift
                fish.speed = 0.2 * difficultyMult
                -- Slow angle adjustment towards target
                local diff = (fish.targetAngle - fish.angle + 180) % 360 - 180
                fish.angle = fish.angle + diff * 0.05
                
                if fish.timer <= 0 then
                    fish.state = "dart"
                    fish.timer = math.random(10, 30)
                    -- Pick a dart angle that roughly points back to base if too far
                    local dx = fish.baseX - fish.x
                    local dy = fish.baseY - fish.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist > 60 then
                        fish.targetAngle = math.deg(math.atan2(dy, dx))
                    else
                        fish.targetAngle = fish.angle + math.random(-45, 45)
                    end
                end
            elseif fish.state == "dart" then
                -- Quick burst
                fish.speed = 1.5 * difficultyMult
                -- Faster angle adjustment
                local diff = (fish.targetAngle - fish.angle + 180) % 360 - 180
                fish.angle = fish.angle + diff * 0.2
                
                if fish.timer <= 0 then
                    fish.state = "drift"
                    fish.timer = math.random(50, 150)
                end
            end

            -- Move fish
            local rad = math.rad(fish.angle)
            local vx = math.cos(rad) * fish.speed
            local vy = math.sin(rad) * fish.speed
            
            local nx = fish.x + vx
            local ny = fish.y + vy

            -- Collision/Boundary check
            if isInAnyObstacle(nx, ny) or nx < 0 or nx > Config.PlayArea.width or ny < 0 or ny > Config.PlayArea.height then
                -- Bounce off or stop
                fish.targetAngle = fish.angle + 180
                fish.state = "drift"
                fish.timer = 50
            else
                fish.x = nx
                fish.y = ny
            end
        end
    end
end

-- ---------------------------------------------------------
-- Input & Logic
-- ---------------------------------------------------------
local function updateInput()
    local boat = State.boat

    -- Decrement Cooldown
    if boat.boostCooldownFrames > 0 then
        boat.boostCooldownFrames = boat.boostCooldownFrames - 1
    end

    -- Trigger Boost (Up button)
    if playdate.buttonJustPressed(playdate.kButtonUp) and boat.boostFrames <= 0 and boat.boostCooldownFrames <= 0 then
        boat.boostSpeed = 11.0 -- Initial arcade burst speed
        boat.boostFrames = 60   -- Duration of boost decay (1.2s at 50fps)
        boat.boostCooldownFrames = math.floor(State.boostCooldownDuration * Config.RefreshRate)
        -- Snap moveAngle to visual angle for immediate lunge in nose direction
        boat.moveAngle = boat.angle
    end

    -- Crank steers the boat (visual angle)
    local crankChange = playdate.getCrankChange()
    boat.angle = boat.angle + crankChange

    -- Calculate angular delta: how misaligned are nose and movement directions?
    local angleDiff = math.abs((boat.angle - boat.moveAngle + 180) % 360 - 180)

    -- Calculate engine speed based on angular misalignment
    local cosAngleDiff = math.cos(math.rad(angleDiff))
    local dragFactor = math.max(0.4, cosAngleDiff)
    local speedMult = 1 + State.upgrades[2].level * 0.15
    local engineTargetSpeed = Config.Boat.baseSpeed * speedMult * dragFactor

    -- Handle Momentum (Bounce or Boost)
    if boat.bounceFrames > 0 then
        -- While bouncing, speed decays from the impact force toward engine speed
        boat.currentSpeed = boat.bounceSpeed
        boat.bounceSpeed = boat.bounceSpeed * 0.92 -- Gentle decay
        boat.bounceFrames = boat.bounceFrames - 1
        
        -- Override drift: keep the boat moving in the reflected bounce direction
        if boat.bounceFrames == 0 then
            boat.bounceSpeed = 0
        end
    elseif boat.boostFrames > 0 then
        -- Arcade Boost logic: propel forward and decay
        boat.currentSpeed = math.max(engineTargetSpeed, boat.boostSpeed)
        boat.boostSpeed = boat.boostSpeed * 0.97 -- Decay multiplier (lose 3% per frame)
        boat.boostFrames = boat.boostFrames - 1
        
        -- During boost, align movement direction with nose faster than normal
        boat.moveAngle = boat.moveAngle + (boat.angle - boat.moveAngle) * 0.2
        
        if boat.boostFrames == 0 then
            boat.boostSpeed = 0
        end
    else
        -- Normal driving physics
        boat.currentSpeed = engineTargetSpeed
        -- Gradually align movement angle toward visual angle (drift)
        boat.moveAngle = boat.moveAngle + (boat.angle - boat.moveAngle) * Config.Boat.driftWeight
    end

    -- Calculate velocity from movement angle at current speed
    local moveAngle_rad = math.rad(boat.moveAngle - 90)
    boat.velocity_x = math.cos(moveAngle_rad) * boat.currentSpeed
    boat.velocity_y = math.sin(moveAngle_rad) * boat.currentSpeed

    -- Apply velocity to position (top-down)
    boat.x = boat.x + boat.velocity_x
    boat.y = boat.y + boat.velocity_y

    -- Use actual boat graphic bounds (scaled for 40x40)
    local boatFront = 12  -- pixels from center to nose
    local boatBack = 12   -- pixels from center to stern
    local boatSide = 8    -- pixels from center to side edge
    local playArea = Config.PlayArea

    -- Check for boundary collision (play area limit)
    -- Skip checks if we just bounced (cooldown to prevent jitter)
    local collisionDetected = false
    if boat.bounceFrames <= 0 then
        -- Calculate four corners of boat bounding box (rotated by boat angle)
        local angleRad = math.rad(boat.angle)
        local cosA = math.cos(angleRad)
        local sinA = math.sin(angleRad)

        local corners = {
            { boat.x - boatSide * cosA + boatFront * sinA, boat.y - boatSide * sinA - boatFront * cosA }, -- front-left
            { boat.x + boatSide * cosA + boatFront * sinA, boat.y + boatSide * sinA - boatFront * cosA }, -- front-right
            { boat.x - boatSide * cosA - boatBack * sinA,  boat.y - boatSide * sinA + boatBack * cosA  }, -- back-left
            { boat.x + boatSide * cosA - boatBack * sinA,  boat.y + boatSide * sinA + boatBack * cosA  }, -- back-right
        }
        boat.corners = corners -- Store for debug drawing

        for _, corner in ipairs(corners) do
            if corner[1] < 0 or corner[1] > playArea.width or
               corner[2] < 0 or corner[2] > playArea.height then
                collisionDetected = true
                break
            end
            if levelCollisionImage and levelCollisionImage:sample(corner[1], corner[2]) ~= gfx.kColorClear then
                collisionDetected = true
                break
            end
        end
        if not collisionDetected and levelCollisionImage then
            if levelCollisionImage:sample(boat.x, boat.y) ~= gfx.kColorClear then
                collisionDetected = true
            end
        end
    end

    if collisionDetected then
        -- Rewind position to previous frame to avoid "teleporting" into the wall at high speed
        boat.x = boat.x - boat.velocity_x
        boat.y = boat.y - boat.velocity_y

        -- 1. Find collision normal
        local nx, ny = 0, 0
        local sampleDist = 20
        for a = 0, 7 do
            local ang = a * (math.pi / 4)
            local sx = boat.x + math.cos(ang) * sampleDist
            local sy = boat.y + math.sin(ang) * sampleDist
            local hitting = false
            if sx < 0 or sx > playArea.width or sy < 0 or sy > playArea.height then hitting = true
            elseif levelCollisionImage and levelCollisionImage:sample(sx, sy) ~= gfx.kColorClear then hitting = true end
            if hitting then nx = nx - math.cos(ang) ny = ny - math.sin(ang) end
        end
        local nLen = math.sqrt(nx * nx + ny * ny)
        if nLen > 0 then nx, ny = nx / nLen, ny / nLen else nx, ny = -boat.velocity_x, -boat.velocity_y end

        -- 2. Physical Bounce Impulse
        -- Nudge 4px to give some breathing room
        boat.x = boat.x + nx * 4
        boat.y = boat.y + ny * 4

        -- Calculate reflection angle using normal velocity
        local moveAngle_rad = math.rad(boat.moveAngle - 90)
        local vx = math.cos(moveAngle_rad) * engineTargetSpeed
        local vy = math.sin(moveAngle_rad) * engineTargetSpeed

        local dot = vx * nx + vy * ny
        local rx = vx - 2 * dot * nx
        local ry = vy - 2 * dot * ny
        
        -- Set the bounce state: reflect at normal driving speed
        boat.moveAngle = math.deg(math.atan2(ry, rx)) + 90
        boat.bounceSpeed = engineTargetSpeed 
        boat.bounceFrames = 12 -- Slightly longer bounce for stability
        boat.currentSpeed = engineTargetSpeed
        
        -- Cancel boost on impact
        boat.boostSpeed = 0
        boat.boostFrames = 0
        
        -- Clear wake so it doesn't look weird during the fast movement
        State.wake = {}
    end

    -- ---------------------------------------------------------
    -- ANTI-STUCK: Persistent overlap resolution
    -- Runs every frame. If any part of the hull is in land,
    -- calculate a repulsion vector to push it out.
    -- ---------------------------------------------------------
    local isStuck = false
    local angleRad = math.rad(boat.angle)
    local cosA = math.cos(angleRad)
    local sinA = math.sin(angleRad)
    local checkPoints = {
        { boat.x, boat.y }, -- center
        { boat.x - boatSide * cosA + boatFront * sinA, boat.y - boatSide * sinA - boatFront * cosA }, -- front-left
        { boat.x + boatSide * cosA + boatFront * sinA, boat.y + boatSide * sinA - boatFront * cosA }, -- front-right
        { boat.x - boatSide * cosA - boatBack * sinA,  boat.y - boatSide * sinA + boatBack * cosA  }, -- back-left
        { boat.x + boatSide * cosA - boatBack * sinA,  boat.y + boatSide * sinA + boatBack * cosA  }, -- back-right
        -- Mid-points
        { boat.x - boatSide * cosA, boat.y - boatSide * sinA }, -- mid-left
        { boat.x + boatSide * cosA, boat.y + boatSide * sinA }, -- mid-right
        { boat.x + boatFront * sinA, boat.y - boatFront * cosA }, -- nose
        { boat.x - boatBack * sinA,  boat.y + boatBack * cosA  }, -- stern
        -- Extra stern points to prevent "catching" the back
        { boat.x - (boatSide * 0.5) * cosA - boatBack * sinA, boat.y - (boatSide * 0.5) * sinA + boatBack * cosA },
        { boat.x + (boatSide * 0.5) * cosA - boatBack * sinA, boat.y + (boatSide * 0.5) * sinA + boatBack * cosA },
    }

    local repulsionX, repulsionY = 0, 0
    for _, p in ipairs(checkPoints) do
        local hitting = false
        if p[1] < 0 or p[1] > playArea.width or p[2] < 0 or p[2] > playArea.height then
            hitting = true
        elseif levelCollisionImage and levelCollisionImage:sample(p[1], p[2]) ~= gfx.kColorClear then
            hitting = true
        end

        if hitting then
            isStuck = true
            -- Calculate vector from stuck point to boat center
            local dx = boat.x - p[1]
            local dy = boat.y - p[2]
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist > 0 then
                repulsionX = repulsionX + (dx / dist)
                repulsionY = repulsionY + (dy / dist)
            else
                -- If center is stuck, use a default fallback (push away from previous movement)
                repulsionX = repulsionX - boat.velocity_x
                repulsionY = repulsionY - boat.velocity_y
            end
        end
    end

    if isStuck then
        local rLen = math.sqrt(repulsionX * repulsionX + repulsionY * repulsionY)
        if rLen > 0 then
            local nx, ny = repulsionX / rLen, repulsionY / rLen
            -- Forcefully nudge boat away from the stuck points (5.0px per frame)
            boat.x = boat.x + nx * 5.0
            boat.y = boat.y + ny * 5.0
        end
    end

    -- Check for littleguy collision (trigger dock prompt)
    local dx = boat.x - State.littleguy.x
    local dy = boat.y - State.littleguy.y
    local distSq = dx * dx + dy * dy
    local lgRadius = State.littleguy.radius
    if distSq < (lgRadius * lgRadius) then
        State.isPaused = true
        State.pausedByDock = true
    end

    -- Record stern position for wake trail (using visual angle for alignment)
    local angleRad = math.rad(State.boat.angle - 90)
    local dirX = math.cos(angleRad)
    local dirY = math.sin(angleRad)

    local sternOffset = 12 -- Distance from center to stern in the 40x40 sprite
    local sternWx = boat.x - dirX * sternOffset
    local sternWy = boat.y - dirY * sternOffset
    local right_wx =  dirY
    local right_wy = -dirX

    local wake = State.wake
    local wakeMax = math.floor(Config.WakeMaxLength * (1 + State.upgrades[3].level * 0.1))

    if #wake == 0 then
        local p = table.remove(State.wakePool) or {}
        p.wx, p.wy, p.rx, p.ry = sternWx, sternWy, right_wx, right_wy
        table.insert(wake, 1, p)
    else
        local prev = wake[1]
        local dx = sternWx - prev.wx
        local dy = sternWy - prev.wy
        local dist = math.sqrt(dx * dx + dy * dy)
        
        -- If we've moved significantly, fill the gap with 1px segments
        if dist >= 1 then
            local steps = math.floor(dist)
            local ux, uy = dx / dist, dy / dist
            
            for i = 1, steps do
                local p = table.remove(State.wakePool) or {}
                -- Interpolate along the path
                p.wx = prev.wx + ux * i
                p.wy = prev.wy + uy * i
                p.rx, p.ry = right_wx, right_wy
                
                table.insert(wake, 1, p)
                
                -- Enforce the tail limit inside the loop
                if #wake > wakeMax then
                    local removed = table.remove(wake)
                    table.insert(State.wakePool, removed)
                end
            end
        end
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
                -- Catch fish inside the polygon (80% coverage check)
                local caught = 0
                for _, f in ipairs(State.fish) do
                    if f.alive then
                        local size = f.size or 20
                        local w = (size * 1.5) / 2
                        local h = (size * 0.7) / 2
                        local rad = math.rad(f.angle or 0)
                        local cosA = math.cos(rad)
                        local sinA = math.sin(rad)
                        
                        -- Define 5 points to check (Center, Head, Tail, Left, Right)
                        local points = {
                            {f.x, f.y},                                -- Center
                            {f.x + cosA * w, f.y + sinA * w},          -- Head
                            {f.x - cosA * w, f.y - sinA * w},          -- Tail
                            {f.x - sinA * h, f.y + cosA * h},          -- Left Side
                            {f.x + sinA * h, f.y - cosA * h}           -- Right Side
                        }
                        
                        local pointsInside = 0
                        for p = 1, 5 do
                            if pointInPolygon(points[p][1], points[p][2], poly) then
                                pointsInside = pointsInside + 1
                            end
                        end
                        
                        -- Require 80% (4 out of 5) points inside to catch
                        if pointsInside >= 4 then
                            f.alive = false
                            State.money = State.money + 1 + State.upgrades[1].level
                            caught = caught + 1
                        end
                    end
                end

                State.hold = State.hold + caught
                
                -- Recycle wake into pool after catching
                for _, wp in ipairs(wake) do
                    table.insert(State.wakePool, wp)
                end
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
    gfx.setColor(gfx.kColorWhite)

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

local function drawBoat(x, y, angle)
    -- Draw boat sprite (rotated programmatically)
    if boatImage then
        boatImage:drawRotated(x, y, angle)
    end
end

local function drawBoostIndicator()
    local boat = State.boat
    local cooldownMax = math.floor(State.boostCooldownDuration * Config.RefreshRate)
    
    -- Always draw the background circle as a "recharging" UI element
    local margin = 20
    local x = 400 - margin
    local y = 240 - margin
    local radius = 12
    
    gfx.setLineWidth(2)
    
    if boat.boostCooldownFrames > 0 then
        -- Draw empty-ish circle with progress fill
        gfx.setColor(gfx.kColorWhite)
        gfx.drawCircleAtPoint(x, y, radius)
        
        local fraction = boat.boostCooldownFrames / cooldownMax
        -- Fill up as it recharges: from 0 (top) around 360 degrees
        local d = (radius - 3) * 2
        gfx.fillEllipseInRect(x - (radius - 3), y - (radius - 3), d, d, 0, 360 * (1 - fraction))
    elseif boat.boostFrames > 0 then
        -- Boost active: solid white circle with inverted dot?
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(x, y, radius)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(x, y, 4)
    else
        -- Ready to use: double circle or something distinct
        gfx.setColor(gfx.kColorWhite)
        gfx.drawCircleAtPoint(x, y, radius)
        gfx.fillCircleAtPoint(x, y, radius - 5)
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
    if #wake >= 2 then
        gfx.setColor(uiColor)
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
                local img = fishImageCache[f.size]
                if img then
                    img:drawRotated(fx, fy, f.angle or 0)
                end
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

-- ---------------------------------------------------------
-- Dock Screen
-- ---------------------------------------------------------
local function drawDockScreen()
    gfx.clear(gfx.kColorBlack)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    if dockImage then
        dockImage:draw(0, 0)
    else
        gfx.drawText("DOCK (Image missing)", 100, 100)
    end
end

-- ---------------------------------------------------------
-- Upgrade Screen
-- ---------------------------------------------------------
local function drawUpgradeScreen()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Wallet footer (more visually pleasing at bottom)
    gfx.drawLine(0, 210, 400, 210)
    gfx.setFont(roobert24)
    gfx.drawText("$" .. State.money, 10, 212)
    gfx.setFont(roobert11)
    gfx.drawText("D-Pad: Select   A: Buy Upgrade   B: Back", 140, 218)

    -- Grid logic (2x2)
    local padding = 10
    local gridY = 10
    local gridH = 190
    local cellW = (400 - padding * 3) / 2
    local cellH = (gridH - padding) / 2

    for i, upgrade in ipairs(State.upgrades) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = padding + col * (cellW + padding)
        local y = gridY + row * (cellH + padding)

        local isSelected = (i == State.selectedUpgrade)

        -- Draw box
        if isSelected then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(x, y, cellW, cellH)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(x, y, cellW, cellH)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        -- Name
        gfx.setFont(roobert24)
        gfx.drawText(upgrade.name, x + 10, y + 10)

        -- Level
        gfx.setFont(roobert11)
        local maxLevel = (i == 2 or i == 3) and 12 or 24
        gfx.drawText("Level " .. upgrade.level .. " / " .. maxLevel, x + 10, y + 45)

        -- Cost
        if upgrade.level < maxLevel then
            local nextCost = calculateUpgradeCost(i, upgrade.level + 1)
            local canAfford = State.money >= nextCost
            local costStr = "Cost: $" .. nextCost
            if not canAfford and not isSelected then
                -- Optional: draw cost differently if unaffordable?
            end
            gfx.drawText(costStr, x + 10, y + 65)
        else
            gfx.drawText("MAXED", x + 10, y + 65)
        end
    end

    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setFont(nil)
end

-- ---------------------------------------------------------
-- Music Screen
-- ---------------------------------------------------------
local function drawMusicScreen()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Header
    gfx.setFont(roobert24)
    gfx.drawText("SOUNDTRACK", 120, 10)
    gfx.drawLine(0, 40, 400, 40)

    -- 3x2 Grid (3 columns, 2 rows)
    local colPadding = 30
    local rowPadding = 10
    local tapeW, tapeH = 75, 74
    local gridWidth = (3 * tapeW) + (2 * colPadding)
    local startX = (400 - gridWidth) / 2
    local startY = 55

    for i = 1, 6 do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = startX + col * (tapeW + colPadding)
        local y = startY + row * (tapeH + rowPadding)

        local isCursor = (i == State.musicSelectionIndex)
        local isSelected = (i == State.selectedMusic)

        -- Selection highlight (box behind cursor)
        if isCursor then
            gfx.setLineWidth(3)
            gfx.drawRect(x - 5, y - 5, tapeW + 10, tapeH + 10)
        end

        -- Draw Tape (Full size 75x74)
        if tapeImage then
            tapeImage:draw(x, y)
        else
            gfx.drawRect(x, y, tapeW, tapeH)
            gfx.drawText("TAPE " .. i, x + 5, y + 25)
        end

        -- "Playing" or "Active" indicator
        if isSelected then
            gfx.fillCircleAtPoint(x + tapeW - 8, y + 8, 5)
        end
    end

    -- Footer
    gfx.drawLine(0, 210, 400, 210)
    gfx.setFont(roobert11)
    gfx.drawText("D-Pad: Navigate   A: Select Track   B: Back", 100, 218)
    
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
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
    local y = 24
    for i = 1, #State.upgrades do
        local upgrade = State.upgrades[i]
        local nextCost = calculateUpgradeCost(i, upgrade.level + 1)
        local maxLevel = (i == 2 or i == 3) and 12 or 24

        if i == State.debugSelectedUpgrade then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(0, y - 1, 400, 14)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        local levelStr = "L" .. upgrade.level .. "/" .. maxLevel
        local costStr  = upgrade.level < maxLevel and ("Next:$" .. nextCost) or "MAXED"
        gfx.drawText(string.format("%-8s  %-8s  %s", upgrade.name, levelStr, costStr), 8, y)

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
    local fishValue = 1 + State.upgrades[1].level
    gfx.drawText(string.format("Fish Value: $%d each", fishValue), 8, y)
    y = y + 10
    gfx.drawLine(0, y + 1, 200, y + 1)
    y = y + 4
    gfx.drawText("Runs: " .. State.totalRunsPlayed .. "   Money: $" .. State.money, 8, y)
    y = y + 12

    -- Controls footer
    gfx.drawLine(0, 224, 400, 224)
    gfx.setFont(nil)  -- smallest font for controls
    gfx.drawText("U/D:select  L/R:level  A:buy  B:exit  Menu+A:+$500  Menu+B:reset", 4, 227)
end

-- ---------------------------------------------------------
-- Secret Debug Menu
-- ---------------------------------------------------------
local function drawSecretMenu()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setFont(roobert24)
    gfx.drawText("SECRET SETTINGS", 100, 10)
    gfx.drawLine(0, 40, 400, 40)
    gfx.setFont(roobert11)

    local items = {
        { name = "Value", type = "upgrade", index = 1, max = 24 },
        { name = "Speed", type = "upgrade", index = 2, max = 12 },
        { name = "Line",  type = "upgrade", index = 3, max = 12 },
        { name = "Fish 1", type = "fishSize", index = 1, max = 100 },
        { name = "Fish 2", type = "fishSize", index = 2, max = 100 },
        { name = "Fish 3", type = "fishSize", index = 3, max = 100 },
        { name = "Fish 4", type = "fishSize", index = 4, max = 100 },
        { name = "W-Size",  type = "waveScale", value = State.waveScale },
        { name = "W-Anim",  type = "waveAnim", value = State.waveAnimSpeed },
        { name = "W-Count", type = "waveCount", value = State.waveCount },
        { name = "F-Count", type = "fishCount", value = State.fishCount },
        { name = "F-Speed", type = "fishSpeed", value = State.fishSpeedMult },
        { name = "B-Cooldown", type = "boostCooldown", value = State.boostCooldownDuration },
        { name = "Markers", type = "toggle", key = "showFishMarkers" },
    }

    -- Scrolling logic: show max 8 items at a time
    local scrollIdx = 0
    if State.secretMenuIndex > 8 then
        scrollIdx = State.secretMenuIndex - 8
    end

    local startY = 55
    local spacing = 22
    local xLabel = 20
    local xSlider = 120
    local sliderWidth = 200

    -- Set clipping rect to keep items below the header
    gfx.setClipRect(0, 42, 400, 198)

    for i, item in ipairs(items) do
        local y = startY + (i - 1 - scrollIdx) * spacing
        local isSelected = (i == State.secretMenuIndex)
        
        if isSelected then
            gfx.fillTriangle(xLabel - 15, y + 2, xLabel - 5, y + 7, xLabel - 15, y + 12)
        end

        gfx.drawText(item.name, xLabel, y)

        if item.type == "upgrade" or item.type == "fishSize" or item.type == "waveScale" or item.type == "waveAnim" or item.type == "waveCount" or item.type == "fishCount" or item.type == "fishSpeed" or item.type == "boostCooldown" or item.type == "smokeScale" or item.type == "smokeFreq" then
            local val, min, max
            if item.type == "upgrade" then
                val = State.upgrades[item.index].level
                max = item.max
                min = -max
            elseif item.type == "fishSize" then
                val = State.fishSizes[item.index]
                min = 1
                max = item.max
            elseif item.type == "waveScale" then
                val = math.floor(State.waveScale * 100)
                min = 10
                max = 200
            elseif item.type == "waveAnim" then
                val = State.waveAnimSpeed
                min = 1
                max = 10
            elseif item.type == "waveCount" then
                val = State.waveCount
                min = 0
                max = 300
            elseif item.type == "fishCount" then
                val = State.fishCount
                min = 1
                max = 50
            elseif item.type == "fishSpeed" then
                val = math.floor(State.fishSpeedMult * 10)
                min = 1
                max = 50
            elseif item.type == "boostCooldown" then
                val = math.floor(State.boostCooldownDuration * 10)
                min = 0
                max = 100
            elseif item.type == "smokeScale" then
                val = math.floor(State.smokeScale * 100)
                min = 10
                max = 300
            elseif item.type == "smokeFreq" then
                val = State.smokeFreq
                min = 5
                max = 250
            end

            -- Draw slider bar
            gfx.drawRect(xSlider, y + 6, sliderWidth, 4)
            -- Draw handle
            local pct = (val - min) / (max - min)
            local handleX = xSlider + (pct * sliderWidth)
            gfx.fillRect(handleX - 5, y, 10, 15)
            -- Draw value text
            local displayVal = tostring(val)
            if item.type == "waveScale" or item.type == "smokeScale" then displayVal = val .. "%"
            elseif item.type == "fishSpeed" then displayVal = (val/10) .. "x"
            elseif item.type == "boostCooldown" then displayVal = (val/10) .. "s" end
            gfx.drawText(displayVal, xSlider + sliderWidth + 10, y)

        elseif item.type == "toggle" then
            local status = State[item.key] and "ON" or "OFF"
            gfx.drawText(status, xSlider, y)
        end
    end

    gfx.clearClipRect()

    -- Draw scroll indicators
    if scrollIdx > 0 then
        gfx.fillTriangle(380, 45, 390, 45, 385, 38)
    end
    if scrollIdx < #items - 8 then
        gfx.fillTriangle(380, 230, 390, 230, 385, 237)
    end
end

-- ---------------------------------------------------------
-- Main Loop
-- ---------------------------------------------------------
function playdate.update()
    -- A + B pressed together = enter Secret Menu
    if (playdate.buttonJustPressed(playdate.kButtonA) and playdate.buttonIsPressed(playdate.kButtonB)) or
       (playdate.buttonJustPressed(playdate.kButtonB) and playdate.buttonIsPressed(playdate.kButtonA)) then
        State.currentScreen = "secret_menu"
        return
    end

    -- Menu button shortcuts
    if playdate.buttonJustPressed(playdate.kButtonMenu) then
        if playdate.buttonIsPressed(playdate.kButtonA) then
            State.currentScreen = "debug"
        elseif playdate.buttonIsPressed(playdate.kButtonB) then
            for i = 1, #State.upgrades do State.upgrades[i].level = 0 end
            State.money = 0
            State.totalRunsPlayed = 0
        elseif playdate.buttonIsPressed(playdate.kButtonRight) then
            State.money = State.money + 500
        else
            State.debugEnabled = not State.debugEnabled
        end
    end

    -- ---------------------------------------------------------
    -- 1. State Updates
    -- ---------------------------------------------------------
    if State.currentScreen == "game" then
        if not State.isPaused then
            updateInput()
            updateFishMovement()
            updateLittleGuyMovement()
            updateWaves()
            
            local time = State.totalFramesPlayed
            State.totalFramesPlayed = time + 1
        end

        if State.isPaused then
            if playdate.buttonJustPressed(playdate.kButtonA) then
                State.isPaused = false
                State.currentScreen = "dock"
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                resetRound()
            end
        end

    elseif State.currentScreen == "secret_menu" then
        local numItems = 14
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            State.secretMenuIndex = math.max(1, State.secretMenuIndex - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            State.secretMenuIndex = math.min(numItems, State.secretMenuIndex + 1)
        end

        local idx = State.secretMenuIndex
        if idx <= 3 then -- Upgrades
            local uIdx = idx
            local maxLevel = (uIdx == 2 or uIdx == 3) and 12 or 24
            local minLevel = -maxLevel
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                State.upgrades[uIdx].level = math.max(minLevel, State.upgrades[uIdx].level - 1)
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                State.upgrades[uIdx].level = math.min(maxLevel, State.upgrades[uIdx].level + 1)
            end
        elseif idx >= 4 and idx <= 7 then -- Fish Sizes
            local sIdx = idx - 3
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                State.fishSizes[sIdx] = math.max(1, State.fishSizes[sIdx] - 1)
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                State.fishSizes[sIdx] = math.min(100, State.fishSizes[sIdx] + 1)
            end
        elseif idx == 8 then -- Wave Size
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                State.waveScale = math.max(0.1, State.waveScale - 0.1)
                preScaleWaves()
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                State.waveScale = math.min(2.0, State.waveScale + 0.1)
                preScaleWaves()
            end
        elseif idx == 9 then -- Wave Animation Speed
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                State.waveAnimSpeed = math.min(10, State.waveAnimSpeed + 1)
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                State.waveAnimSpeed = math.max(1, State.waveAnimSpeed - 1)
            end
        elseif idx == 10 then -- Wave Count
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                State.waveCount = math.max(0, State.waveCount - 10)
                initWaves()
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                State.waveCount = math.min(300, State.waveCount + 10)
                initWaves()
            end
        elseif idx == 11 then -- Fish Count
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                State.fishCount = math.max(1, State.fishCount - 1)
                spawnFish()
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                State.fishCount = math.min(50, State.fishCount + 1)
                spawnFish()
            end
        elseif idx == 12 then -- Fish Speed
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                State.fishSpeedMult = math.max(0.1, State.fishSpeedMult - 0.1)
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                State.fishSpeedMult = math.min(5.0, State.fishSpeedMult + 0.1)
            end
        elseif idx == 13 then -- Boost Cooldown
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                State.boostCooldownDuration = math.max(0.0, State.boostCooldownDuration - 0.1)
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                State.boostCooldownDuration = math.min(10.0, State.boostCooldownDuration + 0.1)
            end
        elseif idx == 14 then -- Markers
            if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
                State.showFishMarkers = not State.showFishMarkers
            end
        end

        if playdate.buttonJustPressed(playdate.kButtonA) then
            resetRound()
            State.currentScreen = "game"
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            State.currentScreen = "game"
        end

    elseif State.currentScreen == "dock" then
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            resetRound()
            State.currentScreen = "game"
        elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.currentScreen = "upgrade"
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.currentScreen = "music"
        end

    elseif State.currentScreen == "upgrade" then
        if playdate.buttonJustPressed(playdate.kButtonB) then
            State.currentScreen = "dock"
        else
            local sel = State.selectedUpgrade
            local numUpgrades = #State.upgrades
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                if sel > 2 then State.selectedUpgrade = sel - 2 end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                if sel + 2 <= numUpgrades then State.selectedUpgrade = sel + 2 end
            elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
                if sel % 2 == 0 then State.selectedUpgrade = sel - 1 end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                if sel % 2 == 1 and sel + 1 <= numUpgrades then State.selectedUpgrade = sel + 1 end
            end

            sel = State.selectedUpgrade
            if playdate.buttonJustPressed(playdate.kButtonA) then
                local nextLevel = State.upgrades[sel].level + 1
                local maxLevel = (sel == 2 or sel == 3) and 12 or 24
                if nextLevel <= maxLevel then
                    local cost = calculateUpgradeCost(sel, nextLevel)
                    if State.money >= cost then
                        State.money = State.money - cost
                        State.upgrades[sel].level = nextLevel
                    end
                end
            end
        end

    elseif State.currentScreen == "music" then
        if playdate.buttonJustPressed(playdate.kButtonB) then
            State.currentScreen = "dock"
        else
            local sel = State.musicSelectionIndex
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                if sel > 3 then State.musicSelectionIndex = sel - 3 end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                if sel <= 3 then State.musicSelectionIndex = sel + 3 end
            elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
                if sel % 3 ~= 1 then State.musicSelectionIndex = sel - 1 end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                if sel % 3 ~= 0 then State.musicSelectionIndex = sel + 1 end
            end

            if playdate.buttonJustPressed(playdate.kButtonA) then
                State.selectedMusic = State.musicSelectionIndex
            end
        end

    elseif State.currentScreen == "debug" then
        local sel = State.debugSelectedUpgrade
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            State.debugSelectedUpgrade = math.max(1, sel - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            State.debugSelectedUpgrade = math.min(#State.upgrades, sel + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.upgrades[sel].level = math.max(0, State.upgrades[sel].level - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            local maxLevel = (sel == 2 or sel == 3) and 12 or 24
            State.upgrades[sel].level = math.min(maxLevel, State.upgrades[sel].level + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            local nextLevel = State.upgrades[sel].level + 1
            local maxLevel = (sel == 2 or sel == 3) and 12 or 24
            if nextLevel <= maxLevel then
                local cost = calculateUpgradeCost(sel, nextLevel)
                if State.money >= cost then
                    State.money = State.money - cost
                    State.upgrades[sel].level = nextLevel
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            State.currentScreen = "game"
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
