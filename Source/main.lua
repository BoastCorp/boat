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
        size = { w = 80, l = 80 },
        radius = 40,
        capacity = math.huge, -- Unlimited capacity for time-based runs
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
    Dock = {
        x = 849,
        y = 1148,
        radius = 50, -- Collision radius for the dock
    },
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
    },
    wake = {},
    wakePool = {}, -- Pre-allocated/recycled tables for wake points
    fish = {},
    money = 0,
    hold = 0,
    roundDuration = 1200, -- 50 FPS * 24 seconds = 1200 frames
    roundTime = 0,
    isPaused = false,
    pausedByDock = false,
    currentScreen = "game",  -- "game" or "upgrade"
    upgrades = {
        { name = "Value",    level = 0 },  -- [1] Fish value: +$1 per level
        { name = "Speed",    level = 0 },  -- [2] Boat speed: +15% per level
        { name = "Line",     level = 0 },  -- [3] Wake length: +10% per level
        { name = "Time",     level = 0 },  -- [4] Round time: +3 seconds per level
    },
    selectedUpgrade = 1,
    selectedMusic = 1,          -- Currently active track
    musicSelectionIndex = 1,    -- Cursor position in music menu
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

-- Load level assets
local levelTopImage = gfx.image.new('images/level/2-top')
local levelCollisionImage = gfx.image.new('images/level/2-collision')
local dockImage = gfx.image.new('images/level/dock-splash')
local dockObjectImage = gfx.image.new('images/level/dock')
local tapeImage = gfx.image.new('images/menu/tape')

-- Music
local menuMusic = playdate.sound.fileplayer.new('sound/music/boxset - wedelivery')
if menuMusic then
    menuMusic:setVolume(0.5)
end

-- Load boat sprite (360-degree directional sprite sheet from Rowbot Rally)
local boatSprites = gfx.imagetable.new('images/boat/boat')
local shadowSprites = gfx.imagetable.new('images/boat/shadow')

-- Load fish images
local fishImages = {
    gfx.image.new('images/fish/clownfish'),
    gfx.image.new('images/fish/stur'),
    gfx.image.new('images/fish/anchovy'),
}

-- Load fonts for UI
local roobert24 = gfx.font.new('fonts/Roobert-24-Medium')
local roobert11 = gfx.font.new('fonts/Roobert-11-Medium')

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

-- Check if a coordinate is "Safe Water" (distance away from land)
local function isSafeWater(x, y, radius)
    -- Check center
    if isInAnyObstacle(x, y) then return false end
    
    -- If no radius check needed, we're done
    if not radius or radius <= 0 then return true end
    
    -- Check 8 points around the circle to ensure clearance
    for a = 0, 7 do
        local angle = a * (math.pi / 4)
        local sx = x + math.cos(angle) * radius
        local sy = y + math.sin(angle) * radius
        if isInAnyObstacle(sx, sy) then return false end
    end
    
    return true
end

-- Helper to spawn fish in Schools and Lone Scouts
local function spawnFish()
    local totalFish = 15 -- Set to 15 (base 10 + extra requested)
    State.fish = {}
    
    -- Playable area is 1000x1000 (visual 1400x1400)
    -- Center 1000x1000 means coords from 200 to 1200
    local minX, maxX = 200, 1200
    local minY, maxY = 200, 1200
    
    local fishPlaced = 0
    print("Spawning fish schools...")
    
    -- 1. Spawn Schools (Clusters)
    local numSchools = 3
    local fishPerSchool = 3
    
    for s = 1, numSchools do
        -- Find a safe Anchor Point (50px buffer from land)
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
                local angle = math.random() * 2 * math.pi
                local dist = math.random(15, 60)
                local fx = anchorX + math.cos(angle) * dist
                local fy = anchorY + math.sin(angle) * dist
                
                -- Ensure individual fish is at least in water
                if not isInAnyObstacle(fx, fy) then
                    local randomFishType = math.random(1, #fishImages)
                    fishPlaced = fishPlaced + 1
                    State.fish[fishPlaced] = {
                        x = fx, y = fy, baseX = fx, baseY = fy,
                        alive = true, image = fishImages[randomFishType],
                        movePhase = math.random() * 6.28,
                        moveType = math.random(1, 3)
                    }
                end
            end
        end
    end
    
    print("Spawning lone scouts... Fish so far: " .. fishPlaced)
    
    -- 2. Spawn Lone Scouts (Fill remaining slots)
    local attempts = 0
    while fishPlaced < totalFish and attempts < 200 do
        local fx = math.random(minX, maxX)
        local fy = math.random(minY, maxY)
        
        if isSafeWater(fx, fy, 40) then -- slightly smaller buffer for lone scouts
            local randomFishType = math.random(1, #fishImages)
            fishPlaced = fishPlaced + 1
            State.fish[fishPlaced] = {
                x = fx, y = fy, baseX = fx, baseY = fy,
                alive = true, image = fishImages[randomFishType],
                movePhase = math.random() * 6.28,
                moveType = math.random(1, 3)
            }
        end
        attempts = attempts + 1
    end
    print("Total fish spawned: " .. fishPlaced)
    
    -- Fallback: If we couldn't place any fish, try again with smaller radius
    if fishPlaced == 0 then
        print("Warning: No fish spawned with 50px buffer. Retrying with 15px...")
        local attempts = 0
        while fishPlaced < totalFish and attempts < 200 do
            local fx = math.random(minX, maxX)
            local fy = math.random(minY, maxY)
            if isSafeWater(fx, fy, 15) then
                local randomFishType = math.random(1, #fishImages)
                fishPlaced = fishPlaced + 1
                State.fish[fishPlaced] = {
                    x = fx, y = fy, baseX = fx, baseY = fy,
                    alive = true, image = fishImages[randomFishType],
                    movePhase = math.random() * 6.28,
                    moveType = math.random(1, 3)
                }
            end
            attempts = attempts + 1
        end
    end
end

-- Call initial spawn
spawnFish()

-- ---------------------------------------------------------
-- Progression Formulas
-- ---------------------------------------------------------
local UPGRADE_BASE_PRICES = { 5, 5, 2, 12 }
-- Value=$5, Speed=$5, Line=$2, Capacity=$12

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
    local duration = 24 + (State.upgrades[4].level * 3)
    local fishPerSec = 0.5 -- hypothetical average
    local fishValue = 1 + State.upgrades[1].level
    return math.floor(duration * fishPerSec * fishValue)
end

-- Helper to fully reset boat + round
local function resetRound()
    State.hold = 0
    State.roundTime = 0
    State.roundDuration = (24 + State.upgrades[4].level * 3) * 50
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
    State.totalRunsPlayed = State.totalRunsPlayed + 1
    spawnFish()
end

-- Update fish positions based on movement phase
local function updateFishMovement()
    -- Fish start moving at run 50
    if State.totalRunsPlayed < 50 then
        return
    end

    -- Gentle movement: movement speed starts slow and increases with runs
    local runsPast50 = math.max(0, State.totalRunsPlayed - 50)
    local movementSpeed = 0.03 + (runsPast50 * 0.002)
    movementSpeed = math.min(movementSpeed, 0.15)

    for _, fish in ipairs(State.fish) do
        if fish.alive then
            -- Initialize movement fields if they don't exist
            if not fish.movePhase then
                fish.movePhase = math.random() * 6.28
                fish.moveType = math.random(1, 3)
                fish.baseX = fish.x
                fish.baseY = fish.y
            end

            fish.movePhase = fish.movePhase + movementSpeed

            if fish.moveType == 1 then
                -- Slow gentle drift
                fish.x = fish.baseX + math.sin(fish.movePhase) * 8
                fish.y = fish.baseY + math.cos(fish.movePhase) * 8
            elseif fish.moveType == 2 then
                -- Figure-8
                fish.x = fish.baseX + math.sin(fish.movePhase) * 6
                fish.y = fish.baseY + math.sin(fish.movePhase * 2) * 6
            else
                -- Random drift
                fish.x = fish.baseX + math.sin(fish.movePhase) * 8
                fish.y = fish.baseY + math.cos(fish.movePhase * 1.5) * 8
            end

            -- Push fish out if they entered an obstacle
            if isInAnyObstacle(fish.x, fish.y) then
                fish.x = fish.baseX
                fish.y = fish.baseY
            end
        end
    end
end

-- ---------------------------------------------------------
-- Input & Logic
-- ---------------------------------------------------------
local function updateInput()
    local boat = State.boat

    -- Trigger Boost (Up button)
    if playdate.buttonJustPressed(playdate.kButtonUp) and boat.boostFrames <= 0 then
        boat.boostSpeed = 11.0 -- Initial arcade burst speed
        boat.boostFrames = 60   -- Duration of boost decay (1.2s at 50fps)
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

    -- Use actual boat graphic bounds, not full sprite (Boat is 80x80 but boat graphic is ~50x34)
    local boatFront = 25  -- pixels from center to nose
    local boatBack = 25   -- pixels from center to stern
    local boatSide = 17   -- pixels from center to side edge
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

    -- Check for dock collision (trigger dock prompt)
    local dx = boat.x - Config.Dock.x
    local dy = boat.y - Config.Dock.y
    local distSq = dx * dx + dy * dy
    local dockRadius = Config.Dock.radius
    if distSq < (dockRadius * dockRadius) then
        State.isPaused = true
        State.pausedByDock = true
    end

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
                -- Catch fish inside the polygon
                local caught = 0
                for _, f in ipairs(State.fish) do
                    if f.alive and pointInPolygon(f.x, f.y, poly) then
                        f.alive = false
                        State.money = State.money + 1 + State.upgrades[1].level
                        caught = caught + 1
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

    -- Draw level terrain visual
    if levelTopImage then
        local lx, ly = project(0, 0)
        levelTopImage:draw(lx, ly)
    end

    -- Draw play area boundary
    local playArea = Config.PlayArea
    local x1, y1 = project(0, 0)
    local x2, y2 = project(playArea.width, 0)
    local x3, y3 = project(playArea.width, playArea.height)
    local x4, y4 = project(0, playArea.height)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawLine(x1, y1, x2, y2)
    gfx.drawLine(x2, y2, x3, y3)
    gfx.drawLine(x3, y3, x4, y4)
    gfx.drawLine(x4, y4, x1, y1)
    gfx.setLineWidth(2)

    -- Draw wake as simple lines (fast, no polygon building)
    local wake = State.wake
    local wakeLen = #wake
    if wakeLen >= 2 then
        for i = 1, wakeLen - 1 do
            local x1, y1 = project(wake[i].wx, wake[i].wy)
            local x2, y2 = project(wake[i + 1].wx, wake[i + 1].wy)
            gfx.drawLine(x1, y1, x2, y2)
        end
    end

    -- Draw fish (stationary images)
    for _, f in ipairs(State.fish) do
        if f.alive and f.image then
            local fx, fy = project(f.x, f.y)
            f.image:drawAnchored(fx, fy, 0.5, 0.5)
        end
    end

    -- Draw dock object in the world
    if dockObjectImage then
        local dx, dy = project(Config.Dock.x, Config.Dock.y)
        dockObjectImage:drawAnchored(dx, dy, 0.5, 0.5)
    end

    -- Draw boat (includes shadow with dithering) at screen center
    local boat_screen_x, boat_screen_y = project(State.boat.x, State.boat.y)
    drawBoat(boat_screen_x, boat_screen_y, State.boat.angle)

    -- Debug: Draw hitbox
    if State.debugEnabled and State.boat.corners then
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(1)
        local c = State.boat.corners
        local p1x, p1y = project(c[1][1], c[1][2])
        local p2x, p2y = project(c[2][1], c[2][2])
        local p3x, p3y = project(c[4][1], c[4][2]) -- Note: 1-2-4-3 order for box loop
        local p4x, p4y = project(c[3][1], c[3][2])
        gfx.drawLine(p1x, p1y, p2x, p2y)
        gfx.drawLine(p2x, p2y, p3x, p3y)
        gfx.drawLine(p3x, p3y, p4x, p4y)
        gfx.drawLine(p4x, p4y, p1x, p1y)
    end

    -- Draw indicators pointing to off-screen fish
    drawOffScreenFishIndicators()

    -- Money display
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText("$" .. State.money, 4, 4)

    -- Gas Meter (replaces numerical timer)
    local gasWidth = 100
    local gasHeight = 12
    local gasX = 400 - gasWidth - 10
    local gasY = 10
    
    local fillPercent = math.max(0, (State.roundDuration - State.roundTime) / State.roundDuration)
    local fillWidth = math.floor(gasWidth * fillPercent)
    
    -- Draw meter background/border
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(gasX, gasY, gasWidth, gasHeight)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(gasX, gasY, gasWidth, gasHeight)
    
    -- Draw fill
    if fillWidth > 0 then
        gfx.fillRect(gasX, gasY, fillWidth, gasHeight)
    end

    -- Pause message (displayed over the game)
    if State.isPaused then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(60, 70, 280, 100)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(60, 70, 280, 100)

        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.setFont(roobert24)
        if State.pausedByDock then
            gfx.drawText("DOCK!", 175, 80)
        else
            gfx.drawText("OUT OF GAS!", 135, 80)
        end
        gfx.setFont(roobert11)
        gfx.drawText("Go back to dock?", 150, 115)
        gfx.drawText("A: Yes (Dock)   B: No (Stay)", 115, 140)
        gfx.setFont(nil)
    end

    -- Small debug panel (top-right, tiny font, toggle with Menu button)
    if State.debugEnabled then
        local v  = State.upgrades[1].level
        local sp = State.upgrades[2].level
        local l  = State.upgrades[3].level
        local c  = State.upgrades[4].level
        local income = calculateRunIncome()
        local nextV  = calculateUpgradeCost(1, v + 1)
        local nextSp = calculateUpgradeCost(2, sp + 1)

        -- White background box
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(220, 44, 178, 42)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(220, 44, 178, 42)

        gfx.setFont(nil)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.drawText("V:"..v.." Sp:"..sp.." L:"..l.." C:"..c, 224, 46)
        gfx.drawText("Est. Income: $"..income.."/run", 224, 56)
        gfx.drawText("Next V=$"..nextV.." Sp=$"..nextSp, 224, 66)
        gfx.drawText("Runs:"..State.totalRunsPlayed.."  $"..State.money, 224, 76)
    end
end

-- ---------------------------------------------------------
-- Dock Screen
-- ---------------------------------------------------------
local function drawDockScreen()
    gfx.clear(gfx.kColorWhite)
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
    local maxCapacity = Config.Boat.capacity + (State.upgrades[4].level * 3)
    local fishValue = 1 + State.upgrades[1].level
    gfx.drawText(string.format("Capacity: %d items", maxCapacity), 8, y)
    y = y + 10
    gfx.drawText(string.format("Fish Value: $%d each", fishValue), 8, y)
    y = y + 10
    gfx.drawLine(0, y + 1, 200, y + 1)
    y = y + 4
    gfx.drawText("EST. TOTAL/RUN: $" .. (maxCapacity * fishValue), 8, y)
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
    -- Music management: Play on dock/upgrade/music screens, stop otherwise
    if State.currentScreen == "dock" or State.currentScreen == "upgrade" or State.currentScreen == "music" then
        if menuMusic and not menuMusic:isPlaying() then
            menuMusic:play(0)
        end
    else
        if menuMusic and menuMusic:isPlaying() then
            menuMusic:stop()
        end
    end

    -- A + B pressed together = jump to Tier 2
    if playdate.buttonJustPressed(playdate.kButtonA) and playdate.buttonIsPressed(playdate.kButtonB) then
        State.totalRunsPlayed = 50
        State.money = 300
        State.upgrades[1].level = 5
        State.upgrades[2].level = 3
        State.upgrades[3].level = 5
        State.upgrades[4].level = 2
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
            State.totalFramesPlayed = State.totalFramesPlayed + 1
            State.roundTime = State.roundTime + 1
            if State.roundTime >= State.roundDuration then
                State.isPaused = true
            end
        end

        if State.isPaused then
            if playdate.buttonJustPressed(playdate.kButtonA) then
                State.isPaused = false
                State.currentScreen = "dock"
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                resetRound()
            end
        end
        waterFrameTime = waterFrameTime + 1

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
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                if sel > 2 then State.selectedUpgrade = sel - 2 end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                if sel <= 2 then State.selectedUpgrade = sel + 2 end
            elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
                if sel % 2 == 0 then State.selectedUpgrade = sel - 1 end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                if sel % 2 == 1 then State.selectedUpgrade = sel + 1 end
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
        gfx.clear()
        drawContent()
    elseif State.currentScreen == "dock" then
        drawDockScreen()
    elseif State.currentScreen == "upgrade" then
        drawUpgradeScreen()
    elseif State.currentScreen == "music" then
        drawMusicScreen()
    elseif State.currentScreen == "debug" then
        drawDebugMenu()
    else
        -- Fallback: unknown screen
        gfx.clear(gfx.kColorWhite)
        gfx.drawText("Error: Unknown Screen '" .. tostring(State.currentScreen) .. "'", 10, 100)
    end
end

