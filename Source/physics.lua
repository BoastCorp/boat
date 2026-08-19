import "state"
import "config"

function pointInPolygon(px, py, poly, n)
    n = n or #poly
    local inside = false
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

function isPointInBox(px, py, box)
    return px >= box.x and px <= box.x + box.w and
           py >= box.y and py <= box.y + box.h
end

function isInAnyObstacle(x, y)
    if levelCollisionImage then
        -- In Playdate, sample returns a color. 
        -- If it's a 1-bit collision map, land is usually black (kColorBlack).
        local color = levelCollisionImage:sample(x, y)
        return color == gfx.kColorBlack
    end
    return false
end

function isSafeWater(x, y, radius)
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
    
    -- Check 4 orthogonal points around the circle to ensure clearance from land
    if isInAnyObstacle(x + r, y) then return false end
    if isInAnyObstacle(x - r, y) then return false end
    if isInAnyObstacle(x, y + r) then return false end
    if isInAnyObstacle(x, y - r) then return false end
    
    return true
end

function isOverlappingExistingFish(x, y, size)
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

function updatePhysics()
    local boat = State.boat

    -- Decrement Cooldown
    if boat.boostCooldownFrames > 0 then
        boat.boostCooldownFrames = boat.boostCooldownFrames - 1
    end


    -- Calculate angular delta: how misaligned are nose and movement directions?
    local angleDiff = math.abs((boat.angle - boat.moveAngle + 180) % 360 - 180)

    -- Calculate engine speed based on angular misalignment
    local cosAngleDiff = math.cos(math.rad(angleDiff))
    local dragFactor = math.max(0.4, cosAngleDiff)
    local speedMult = 1 + getEffectiveUpgradeLevel(2) * 0.15
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

        -- Calculate reflection angle using actual current velocity
        local moveAngle_rad = math.rad(boat.moveAngle - 90)
        local vx = math.cos(moveAngle_rad) * boat.currentSpeed
        local vy = math.sin(moveAngle_rad) * boat.currentSpeed

        local dot = vx * nx + vy * ny
        local rx = vx - 2 * dot * nx
        local ry = vy - 2 * dot * ny
        
        -- Set the bounce state: reflect at impact speed
        boat.moveAngle = math.deg(math.atan2(ry, rx)) + 90
        boat.bounceSpeed = boat.currentSpeed 
        boat.bounceFrames = 20 -- Smooth decay over 20 frames
        boat.currentSpeed = boat.bounceSpeed
        
        local isBoosting = boat.boostFrames > 0
        Telemetry.logCollision(boat.currentSpeed, angleDiff, isBoosting)
        
        -- Cancel boost on impact
        boat.boostSpeed = 0
        boat.boostFrames = 0
        
        -- Clear wake so it doesn't look weird during the fast movement
        State.wake = {}
        State.boat.wakeLength = 0
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
    boat.isStuck = isStuck

    -- Check for littleguy collision (trigger dock prompt) using 45x37 rectangular hitbox
    local lg = State.littleguy
    local halfW = lg.width / 2
    local halfH = lg.height / 2
    local collided = false

    if math.abs(boat.x - lg.x) < halfW and math.abs(boat.y - lg.y) < halfH then
        collided = true
    else
        local corners = boat.corners or {}
        for _, corner in ipairs(corners) do
            if math.abs(corner[1] - lg.x) < halfW and math.abs(corner[2] - lg.y) < halfH then
                collided = true
                break
            end
        end
    end

    if collided then
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
    boat.sternX = sternWx
    boat.sternY = sternWy
    local right_wx =  dirY
    local right_wy = -dirX

    local wake = State.wake
    local maxPhysLen = Config.WakeMaxLength * (1 + getEffectiveUpgradeLevel(3) * 0.2)

    if boat.bounceFrames <= 0 and not isStuck then
        if #wake == 0 then
            local p = table.remove(State.wakePool) or {}
            p.wx, p.wy, p.rx, p.ry = sternWx, sternWy, right_wx, right_wy
            p.angle = State.boat.angle
            p.dist = 0
            table.insert(wake, 1, p)
            State.boat.wakeLength = 0
        else
            local prev = wake[1]
            local dx = sternWx - prev.wx
            local dy = sternWy - prev.wy
            local dist = math.sqrt(dx * dx + dy * dy)
            
            local angleDiff = 0
            if prev.angle then
                angleDiff = math.abs(State.boat.angle - prev.angle)
                angleDiff = angleDiff % 360
                if angleDiff > 180 then angleDiff = 360 - angleDiff end
            end
            
            -- Insert point if we moved by segment length OR turned significantly
            if dist >= Config.WakeSegmentLength or (dist >= 1.5 and angleDiff >= 5) then
                local p = table.remove(State.wakePool) or {}
                p.wx, p.wy, p.rx, p.ry = sternWx, sternWy, right_wx, right_wy
                p.angle = State.boat.angle
                p.dist = dist
                table.insert(wake, 1, p)
                State.boat.wakeLength = (State.boat.wakeLength or 0) + dist
                
                -- We've locked in the point, so distance from stern to wake[1] is now 0
                dist = 0
            end
            
            -- Smoothly trim the tail every frame to match max physical length
            local totalVisualLen = (State.boat.wakeLength or 0) + dist
            while #wake > 1 and totalVisualLen > maxPhysLen do
                local excess = totalVisualLen - maxPhysLen
                local lastSegmentDist = wake[#wake - 1].dist or 0
                
                if excess >= lastSegmentDist then
                    local removed = table.remove(wake)
                    table.insert(State.wakePool, removed)
                    State.boat.wakeLength = State.boat.wakeLength - lastSegmentDist
                    wake[#wake].dist = 0
                    totalVisualLen = State.boat.wakeLength + dist
                else
                    local p1 = wake[#wake - 1]
                    local p2 = wake[#wake]
                    local ratio = (lastSegmentDist - excess) / lastSegmentDist
                    p2.wx = p1.wx + (p2.wx - p1.wx) * ratio
                    p2.wy = p1.wy + (p2.wy - p1.wy) * ratio
                    p1.dist = lastSegmentDist - excess
                    State.boat.wakeLength = State.boat.wakeLength - excess
                    break
                end
            end
        end
    else
        -- Recycle existing wake points if we are bouncing or stuck
        if #wake > 0 then
            for _, wp in ipairs(wake) do
                table.insert(State.wakePool, wp)
            end
            State.wake = {}
            State.boat.wakeLength = 0
        end
    end

    -- Loop detection: if stern gets close to an older wake point, catch fish inside
    if #wake >= 3 then
        local threshSq = Config.Catch.closeThreshold * Config.Catch.closeThreshold
        local currentDistToWake1 = math.sqrt((sternWx - wake[1].wx)^2 + (sternWy - wake[1].wy)^2)
        local pathDist = currentDistToWake1
        
        for i = 1, #wake do
            local p = wake[i]
            
            if pathDist >= Config.Catch.minLoopLength then
                local ddx = sternWx - p.wx
                local ddy = sternWy - p.wy
                if ddx * ddx + ddy * ddy <= threshSq then
                -- Broadphase: Calculate bounding box of the closed loop
                local minX, maxX = wake[1].wx, wake[1].wx
                local minY, maxY = wake[1].wy, wake[1].wy
                for j = 2, i do
                    local wp = wake[j]
                    if wp.wx < minX then minX = wp.wx
                    elseif wp.wx > maxX then maxX = wp.wx end
                    if wp.wy < minY then minY = wp.wy
                    elseif wp.wy > maxY then maxY = wp.wy end
                end

                -- Catch fish inside the polygon (80% coverage check)
                local caught = 0
                local totalEarned = 0
                local caughtFishList = {}
                for idx, f in ipairs(State.fish) do
                    if f.alive then
                        -- Only run checks if the fish center is within the loop bounding box
                        if f.x >= minX and f.x <= maxX and f.y >= minY and f.y <= maxY then
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
                                if pointInPolygon(points[p][1], points[p][2], wake, i) then
                                    pointsInside = pointsInside + 1
                                end
                            end
                            
                            -- Require 80% (4 out of 5) points inside to catch
                            if pointsInside >= 4 then
                                f.alive = false
                                
                                -- Determine base value based on size index
                                local baseVal = 1
                                local sizeValues = { 1, 2, 3, 4, 8, 16, 32, 64 }
                                for sizeIdx, sz in ipairs(State.fishSizes) do
                                    if f.size == sz then
                                        baseVal = sizeValues[sizeIdx] or sizeIdx
                                        break
                                    end
                                end
                                local fishVal = baseVal + getEffectiveUpgradeLevel(1)
                                
                                caught = caught + 1
                                totalEarned = totalEarned + fishVal
                                table.insert(caughtFishList, { idx = idx, size = size, val = fishVal })
                            end
                        end
                    end
                end

                if caught == 0 then
                    local nearby = 0
                    local bx, by = State.boat.x, State.boat.y
                    for _, f in ipairs(State.fish) do
                        if f.alive then
                            local dSq = (f.x - bx)^2 + (f.y - by)^2
                            if dSq < 250000 then nearby = nearby + 1 end
                        end
                    end
                    Telemetry.logLoopFail(i, nearby)
                else
                    -- Calculate multipliers
                    local isBoostCatch = State.boat.boostFrames > 0
                    local multiCatchMult = 1.0 + (caught - 1) * 0.5
                    local boostMult = isBoostCatch and 1.5 or 1.0
                    local finalMult = multiCatchMult * boostMult
                    
                    local netPayout = 0
                    for _, item in ipairs(caughtFishList) do
                        local finalVal = math.floor(item.val * finalMult)
                        netPayout = netPayout + finalVal
                        Telemetry.logCatch(item.idx, State.hold + caught, 999, item.size, finalVal, 0, i, #wake)
                    end
                    
                    State.money = State.money + netPayout
                    State.hold = State.hold + caught
                    
                    -- Spawn floating texts relative to boat
                    if isBoostCatch then
                        table.insert(State.floatingTexts, { text = "Boost Catch! +$" .. netPayout, yOffset = -25, timer = 50 })
                    else
                        table.insert(State.floatingTexts, { text = "+$" .. netPayout, yOffset = -25, timer = 50 })
                    end
                    
                    if caught > 1 then
                        table.insert(State.floatingTexts, { text = "x" .. caught, yOffset = -40, timer = 50 })
                    end
                end
                
                -- Recycle wake into pool after catching
                for _, wp in ipairs(wake) do
                    table.insert(State.wakePool, wp)
                end
                State.wake = {}
                State.boat.wakeLength = 0
                break
            end
            end
            
            -- Add the length of the segment starting at this point for the NEXT iteration's check
            pathDist = pathDist + (p.dist or 0)
        end
    end
end

