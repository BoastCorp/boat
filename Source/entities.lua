import "state"
import "config"
import "physics"

function preRenderFishImages()
    fishAnimCache = {}
    local numVertices = 24 -- Smooth enough for pre-rendering
    local freq = 2.0
    
    for _, size in ipairs(State.fishSizes) do
        fishAnimCache[size] = {}
        local w = math.ceil(size * 1.5) + 12
        local h = math.ceil(size * 0.7) + 12
        local a = (size * 1.5) / 2
        local b = (size * 0.7) / 2
        local amp = size * 0.015
        
        -- Pre-render 4 frames of the wave animation
        for frame = 1, 4 do
            local img = gfx.image.new(w, h, gfx.kColorClear)
            local phase = (frame - 1) * (2 * math.pi / 4)
            local coords = {}
            
            for i = 1, numVertices do
                local theta = (2 * math.pi / numVertices) * i
                local ex = a * math.cos(theta)
                local ey = b * math.sin(theta)
                
                local u = 0
                local sideSign = 1
                if theta <= math.pi then
                    u = theta / math.pi
                    sideSign = 1
                else
                    u = (2 * math.pi - theta) / math.pi
                    sideSign = -1
                end
                
                local envelope = math.sin(math.pi * u)
                local wave = amp * envelope * math.sin(2 * math.pi * freq * u - phase)
                
                local lx = ex
                local ly = ey + (sideSign * wave)
                
                table.insert(coords, w/2 + lx)
                table.insert(coords, h/2 + ly)
            end
            
            table.insert(coords, coords[1])
            table.insert(coords, coords[2])
            
            gfx.pushContext(img)
                local poly = playdate.geometry.polygon.new(table.unpack(coords))
                gfx.setColor(gfx.kColorWhite)
                gfx.fillPolygon(poly)
            gfx.popContext()
            
            fishAnimCache[size][frame] = img
        end
    end
end

function preScaleWaves()
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

function initWaves()
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

function updateWaves()
    -- No state to update per-frame, handled in draw
end

function spawnFish()
    local totalFish = State.fishCount
    State.fish = {}
    
    -- Playable area is 1000x1000 (visual 1400x1400)
    -- Center 1000x1000 means coords from 200 to 1200
    local minX, maxX = 200, 1200
    local minY, maxY = 200, 1200
    
    local fishPlaced = 0
    
    -- Dynamically build list of active fish sizes based on Line upgrade level (index 3)
    local activeSizes = { 10, 20, 30, 40 }
    local lineLvl = State.upgrades[3].level
    if lineLvl >= 2 then table.insert(activeSizes, 50) end
    if lineLvl >= 4 then table.insert(activeSizes, 60) end
    if lineLvl >= 6 then table.insert(activeSizes, 70) end
    if lineLvl >= 8 then table.insert(activeSizes, 80) end
    
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
                    
                    local size = activeSizes[math.random(1, #activeSizes)]
                    
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
            local size = math.random(1, 5) == 5 and activeSizes[#activeSizes] or activeSizes[math.random(1, math.max(1, #activeSizes - 1))]
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
                local size = math.random(1, 5) == 5 and activeSizes[#activeSizes] or activeSizes[math.random(1, math.max(1, #activeSizes - 1))]
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

function initLittleGuy()
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

function updateLittleGuyMovement()
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

    -- Boundary check for littleguy (ensure 100px border buffer and no obstacle collision within radius)
    local buffer = 100
    if nx < buffer or nx > Config.PlayArea.width - buffer or ny < buffer or ny > Config.PlayArea.height - buffer or not isSafeWater(nx, ny, lg.radius) then
        lg.targetAngle = lg.angle + 180
        lg.state = "drift"
        lg.timer = 50
    else
        lg.x = nx
        lg.y = ny
    end
end

function updateFishMovement()
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

            -- Collision/Boundary check (reverted to single point check for performance)
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

function drawWavyFish(fx, fy, size, angle)
    local animFrames = fishAnimCache[size]
    if not animFrames then return end
    
    -- Pick frame based on total frames played (cycling every 4 frames)
    local frame = (math.floor(State.totalFramesPlayed / 8) % 4) + 1
    local img = animFrames[frame]
    if img then
        img:drawRotated(fx, fy, angle)
    end
end


