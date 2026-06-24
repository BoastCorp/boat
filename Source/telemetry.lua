-- ---------------------------------------------------------
-- Telemetry & Pacing Analysis Logger
-- ---------------------------------------------------------
Telemetry = {
    -- State variables
    runFrames = 0,
    menuFrames = 0,
    sessionStartFrame = 0,
    runActive = false,
    
    -- Inputs
    runCrankDegrees = 0,
    crankDirChanges = 0,
    lastCrankAngle = 0,
    lastCrankDir = 0,
    
    -- Economics
    runNumber = 0,
    unspentWallet = 0,
    cheapestUpgradeCost = 0,
    
    -- Physics & Obstacles
    collisions = 0,
    lastCollisionFrame = 0,
    collisionChainCount = 0,
    nearMissesCount = 0,
    inNearMissRange = false,
    minNearMissDist = 999,
    farthestDist = 0,
    spawnX = 852,
    spawnY = 1065,
    gridVisited = {},
    
    -- Mechanical Synergy & Excitement
    lastBoostFrame = 0,
    boostsUsed = 0,
    proximityCrankFrames = 0,
    proximityCrankDegrees = 0,
    travelCrankFrames = 0,
    travelCrankDegrees = 0,
    
    -- Fish & Catching
    chaseStartFrames = {},    -- fish_index -> frame_number
    activeChaseTarget = nil,
    targetSwitchCount = 0,
    indicatorAppearFrames = {}, -- fish_index -> frame_number
    catchFrames = {},
    loopsFailed = 0,
    stuckStartFrame = nil,
}

local function formatTime(frames)
    local secs = frames / Config.RefreshRate
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    local ms = math.floor((secs * 100) % 100)
    return string.format("%dm%02d.%02ds", m, s, ms)
end

function Telemetry.init()
    Telemetry.sessionStartFrame = 0
    print("[SESSION_START] time=0.0s wallet=" .. State.money .. " upgrades={V:" .. State.upgrades[1].level .. ",S:" .. State.upgrades[2].level .. ",L:" .. State.upgrades[3].level .. ",C:" .. State.upgrades[4].level .. "}")
end

function Telemetry.logDepartDock()
    Telemetry.runActive = true
    Telemetry.runFrames = 0
    Telemetry.runCrankDegrees = 0
    Telemetry.crankDirChanges = 0
    Telemetry.collisions = 0
    Telemetry.collisionChainCount = 0
    Telemetry.nearMissesCount = 0
    Telemetry.inNearMissRange = false
    Telemetry.minNearMissDist = 999
    Telemetry.farthestDist = 0
    Telemetry.spawnX = State.boat.x
    Telemetry.spawnY = State.boat.y
    Telemetry.gridVisited = {}
    Telemetry.boostsUsed = 0
    Telemetry.proximityCrankFrames = 0
    Telemetry.proximityCrankDegrees = 0
    Telemetry.travelCrankFrames = 0
    Telemetry.travelCrankDegrees = 0
    Telemetry.chaseStartFrames = {}
    Telemetry.activeChaseTarget = nil
    Telemetry.targetSwitchCount = 0
    Telemetry.catchFrames = {}
    Telemetry.loopsFailed = 0
    Telemetry.stuckStartFrame = nil
    
    Telemetry.runNumber = State.totalRunsPlayed + 1
    
    local cheapest = 9999
    for i = 1, #State.upgrades do
        local cost = calculateUpgradeCost(i, State.upgrades[i].level + 1)
        if cost < cheapest then cheapest = cost end
    end
    Telemetry.cheapestUpgradeCost = cheapest
    Telemetry.unspentWallet = State.money
    
    local elapsedStr = formatTime(State.totalFramesPlayed)
    local upgradesStr = string.format("{V:%d,S:%d,L:%d,C:%d}", State.upgrades[1].level, State.upgrades[2].level, State.upgrades[3].level, State.upgrades[4].level)
    print(string.format("[DEPART_DOCK] run=%d time_in_menu=%s wallet=%d upgrades=%s", Telemetry.runNumber, formatTime(Telemetry.menuFrames), State.money, upgradesStr))
    
    Telemetry.menuFrames = 0
end

function Telemetry.logReturnDock(fishSold, moneyEarned)
    Telemetry.runActive = false
    local durationStr = formatTime(Telemetry.runFrames)
    
    -- Map Coverage calculation
    local gridCount = 0
    for _ in pairs(Telemetry.gridVisited) do gridCount = gridCount + 1 end
    local maxGrid = 400 -- 1000x1000 playable area divided into 50x50 cells is 20x20 = 400
    local expRatio = math.min(100, math.floor((gridCount / maxGrid) * 100))
    
    -- Print Map Coverage
    print(string.format("[MAP_COVERAGE] run=%d grid_visited=%d/%d exploration_ratio=%d%% farthest_dist_from_spawn=%d", 
        Telemetry.runNumber, gridCount, maxGrid, expRatio, math.floor(Telemetry.farthestDist)))
    
    -- Print Crank Fatigue
    local avgRpm = 0
    if Telemetry.runFrames > 0 then
        avgRpm = (Telemetry.runCrankDegrees / 360) / (Telemetry.runFrames / (50 * 60)) -- RPM
    end
    print(string.format("[CRANK_LOG] run=%d total_degrees_turned=%d average_rpm=%.1f direction_changes=%d", 
        Telemetry.runNumber, math.floor(Telemetry.runCrankDegrees), avgRpm, Telemetry.crankDirChanges))
        
    -- Print EXCITEMENT CRANK
    local proxRpm = 0
    local travRpm = 0
    if Telemetry.proximityCrankFrames > 0 then
        proxRpm = (Telemetry.proximityCrankDegrees / 360) / (Telemetry.proximityCrankFrames / (50 * 60))
    end
    if Telemetry.travelCrankFrames > 0 then
        travRpm = (Telemetry.travelCrankDegrees / 360) / (Telemetry.travelCrankFrames / (50 * 60))
    end
    local exciteRatio = 0
    if travRpm > 0 then exciteRatio = math.floor((proxRpm / travRpm) * 100) end
    print(string.format("[EXCITEMENT_CRANK] run=%d proximity_rpm=%.1f travel_rpm=%.1f excitement_ratio=%d%%", 
        Telemetry.runNumber, proxRpm, travRpm, exciteRatio))
        
    -- Print RUN PHASE EFFICIENCY (grind decay)
    local numCatches = #Telemetry.catchFrames
    if numCatches >= 2 then
        local midPoint = math.floor(numCatches / 2)
        local firstHalfFrames = Telemetry.catchFrames[midPoint] or 0
        local secondHalfFrames = Telemetry.runFrames - firstHalfFrames
        
        local firstHalfRate = (firstHalfFrames / Config.RefreshRate) / midPoint
        local secondHalfRate = (secondHalfFrames / Config.RefreshRate) / (numCatches - midPoint)
        local decayRatio = 0
        if firstHalfRate > 0 then decayRatio = math.floor((secondHalfRate / firstHalfRate) * 100) end
        
        print(string.format("[RUN_PHASE_EFFICIENCY] run=%d first_half_rate=%.2fs/fish second_half_rate=%.2fs/fish decay_ratio=%d%%", 
            Telemetry.runNumber, firstHalfRate, secondHalfRate, decayRatio))
    end

    -- Dead Cash (unspent logic)
    local unspentPercent = 0
    if Telemetry.unspentWallet > 0 then
        unspentPercent = math.floor((Telemetry.unspentWallet / (Telemetry.unspentWallet + moneyEarned)) * 100)
    end
    print(string.format("[DEAD_CASH] run=%d unspent_wallet=$%d percent_unspent=%d%% cheapest_available_upgrade=$%d", 
        Telemetry.runNumber, Telemetry.unspentWallet, unspentPercent, Telemetry.cheapestUpgradeCost))

    -- Return Dock Summary
    local avgSpeed = 0
    if Telemetry.runFrames > 0 then
        -- Total speed accumulated / frames
        avgSpeed = State.boat.currentSpeed -- Simple representation
    end
    
    print(string.format("[RETURN_DOCK] run=%d duration=%s fish_sold=%d money_earned=%d boosts_used=%d crashes=%d", 
        Telemetry.runNumber, durationStr, fishSold, moneyEarned, Telemetry.boostsUsed, Telemetry.collisions))
end

function Telemetry.logCatch(fishIndex, holdFill, maxCapacity, size, value, multiCatchBonus, pointsInLoop, totalPoints)
    local runTimeStr = formatTime(Telemetry.runFrames)
    
    -- Calculate Wake Waste Ratio
    local wasteRatio = 0
    if totalPoints > 0 then
        wasteRatio = math.floor((1 - (pointsInLoop / totalPoints)) * 100)
    end
    
    print(string.format("[CATCH] time_in_run=%s hold_fill=%d/%d fish_size=%d fish_value=$%d multi_catch_bonus=$%d loop_points=%d", 
        runTimeStr, holdFill, maxCapacity, size, value, multiCatchBonus, pointsInLoop))
        
    print(string.format("[WAKE_WASTE_RATIO] run=%d total_points=%d points_in_loop=%d waste_ratio=%d%%", 
        Telemetry.runNumber, totalPoints, pointsInLoop, wasteRatio))
        
    -- Check if it was a BOOST_CATCH
    local framesSinceBoost = Telemetry.runFrames - Telemetry.lastBoostFrame
    if framesSinceBoost <= 50 then -- within 1.0 second (50 FPS)
        print(string.format("[BOOST_CATCH] time_in_run=%s hold_fill=%d/%d boost_speed=%.2f", 
            runTimeStr, holdFill, maxCapacity, State.boat.currentSpeed))
    end
    
    -- Check Chase Duration
    if Telemetry.chaseStartFrames[fishIndex] then
        local chaseFrames = Telemetry.runFrames - Telemetry.chaseStartFrames[fishIndex]
        local chaseSecs = chaseFrames / Config.RefreshRate
        print(string.format("[CHASE_DURATION] fish_id=%d duration=%.2fs", fishIndex, chaseSecs))
        Telemetry.chaseStartFrames[fishIndex] = nil
    end
    
    table.insert(Telemetry.catchFrames, Telemetry.runFrames)
    
    if Telemetry.activeChaseTarget == fishIndex then
        Telemetry.activeChaseTarget = nil
    end
end

function Telemetry.logLoopFail(wakeLen, nearbyFish)
    Telemetry.loopsFailed = Telemetry.loopsFailed + 1
    local runTimeStr = formatTime(Telemetry.runFrames)
    print(string.format("[LOOP_FAIL] time_in_run=%s wake_len=%d nearby_fish=%d", runTimeStr, wakeLen, nearbyFish))
end

function Telemetry.logBoost()
    Telemetry.boostsUsed = Telemetry.boostsUsed + 1
    Telemetry.lastBoostFrame = Telemetry.runFrames
    local runTimeStr = formatTime(Telemetry.runFrames)
    print(string.format("[BOOST] time_in_run=%s current_speed=%.2f coord={%.0f,%.0f}", 
        runTimeStr, State.boat.currentSpeed, State.boat.x, State.boat.y))
end

function Telemetry.logCollision(impactSpeed, angleDiff, isBoosting)
    Telemetry.collisions = Telemetry.collisions + 1
    local runTimeStr = formatTime(Telemetry.runFrames)
    local stateStr = isBoosting and "boosting" or "normal"
    
    print(string.format("[COLLISION] time_in_run=%s impact_speed=%.2f angle_diff=%.1f state=%s", 
        runTimeStr, impactSpeed, angleDiff, stateStr))
        
    -- Check collision chain (pinballing)
    local diff = Telemetry.runFrames - Telemetry.lastCollisionFrame
    if diff <= 75 then -- 1.5 seconds at 50 FPS
        Telemetry.collisionChainCount = Telemetry.collisionChainCount + 1
        print(string.format("[COLLISION_CHAIN] chain_length=%d current_speed=%.2f coord={%.0f,%.0f}", 
            Telemetry.collisionChainCount, State.boat.currentSpeed, State.boat.x, State.boat.y))
    else
        Telemetry.collisionChainCount = 1
    end
    Telemetry.lastCollisionFrame = Telemetry.runFrames
end

function Telemetry.logStuck(durationSecs)
    print(string.format("[STUCK_RECOVERY] duration=%.2fs coord={%.0f,%.0f}", 
        durationSecs, State.boat.x, State.boat.y))
end

function Telemetry.logUpgrade(name, newLvl, cost, wallet)
    print(string.format("[UPGRADE] run=%d upgrade=%s level=%d cost=$%d remaining_wallet=$%d session_elapsed=%s", 
        Telemetry.runNumber, name, newLvl, cost, wallet, formatTime(State.totalFramesPlayed)))
end

function Telemetry.update()
    if State.currentScreen == "game" then
        if not State.isPaused then
            Telemetry.runFrames = Telemetry.runFrames + 1
            
            -- Stuck tracking
            if State.boat.isStuck then
                if not Telemetry.stuckStartFrame then
                    Telemetry.stuckStartFrame = Telemetry.runFrames
                end
            else
                if Telemetry.stuckStartFrame then
                    local duration = (Telemetry.runFrames - Telemetry.stuckStartFrame) / Config.RefreshRate
                    Telemetry.logStuck(duration)
                    Telemetry.stuckStartFrame = nil
                end
            end
            
            local bx, by = State.boat.x, State.boat.y
            
            -- Farthest distance from spawn
            local dist = math.sqrt((bx - Telemetry.spawnX)^2 + (by - Telemetry.spawnY)^2)
            if dist > Telemetry.farthestDist then Telemetry.farthestDist = dist end
            
            -- Map Coverage Grid Cell Visited
            local cx = math.floor(bx / 50)
            local cy = math.floor(by / 50)
            Telemetry.gridVisited[cx .. "_" .. cy] = true
            
            -- Crank Dynamics
            local change = playdate.getCrankChange()
            Telemetry.runCrankDegrees = Telemetry.runCrankDegrees + math.abs(change)
            
            if math.abs(change) > 0.1 then
                local currentDir = change > 0 and 1 or -1
                if Telemetry.lastCrankDir ~= 0 and currentDir ~= Telemetry.lastCrankDir then
                    Telemetry.crankDirChanges = Telemetry.crankDirChanges + 1
                end
                Telemetry.lastCrankDir = currentDir
            end
            
            -- EXCITEMENT CRANK tracking
            local closeToFish = false
            for idx, f in ipairs(State.fish) do
                if f.alive then
                    local fdist = math.sqrt((bx - f.x)^2 + (by - f.y)^2)
                    if fdist < 100 then
                        closeToFish = true
                    end
                    
                    -- Track off-screen indicators appearance
                    local dx, dy = f.x - bx, f.y - by
                    local isOffScreen = dx < -200 or dx > 200 or dy < -120 or dy > 120
                    if isOffScreen then
                        if not Telemetry.indicatorAppearFrames[idx] then
                            Telemetry.indicatorAppearFrames[idx] = Telemetry.runFrames
                        end
                        
                        -- Track indicator reaction times
                        -- If the boat moves closer to aligning heading with the target
                        local targetAngle = math.deg(math.atan2(dy, dx)) + 90
                        local headingDiff = math.abs((State.boat.angle - targetAngle + 180) % 360 - 180)
                        if headingDiff < 20 and Telemetry.indicatorAppearFrames[idx] then
                            local reaction = (Telemetry.runFrames - Telemetry.indicatorAppearFrames[idx]) / Config.RefreshRate
                            if reaction > 0.2 and reaction < 10.0 then -- Ignore instant alignments
                                print(string.format("[INDICATOR_REACTION] indicator_heading=%.1f initial_boat_heading=%.1f turn_reaction_time=%.2fs", 
                                    targetAngle, State.boat.angle, reaction))
                            end
                            Telemetry.indicatorAppearFrames[idx] = nil
                        end
                    else
                        Telemetry.indicatorAppearFrames[idx] = nil
                    end
                    
                    -- Track fish chases
                    if fdist < 120 then
                        if not Telemetry.chaseStartFrames[idx] then
                            Telemetry.chaseStartFrames[idx] = Telemetry.runFrames
                        end
                        
                        -- Target switching check
                        if Telemetry.activeChaseTarget == nil then
                            Telemetry.activeChaseTarget = idx
                        elseif Telemetry.activeChaseTarget ~= idx and fdist < 60 then
                            -- Player got very close to this new fish instead of original target
                            Telemetry.targetSwitchCount = Telemetry.targetSwitchCount + 1
                            print(string.format("[TARGET_SWITCH] time_in_run=%s distance_from_first=%.1f", 
                                formatTime(Telemetry.runFrames), fdist))
                            Telemetry.activeChaseTarget = idx
                        end
                    else
                        if Telemetry.activeChaseTarget == idx then
                            Telemetry.activeChaseTarget = nil
                        end
                    end
                end
            end
            
            if closeToFish then
                Telemetry.proximityCrankFrames = Telemetry.proximityCrankFrames + 1
                Telemetry.proximityCrankDegrees = Telemetry.proximityCrankDegrees + math.abs(change)
            else
                Telemetry.travelCrankFrames = Telemetry.travelCrankFrames + 1
                Telemetry.travelCrankDegrees = Telemetry.travelCrankDegrees + math.abs(change)
            end
            
            -- Near-Miss logic
            -- If we are close to a wall, moving fast, and haven't hit yet
            local speed = State.boat.currentSpeed
            if speed > 2.5 and levelCollisionImage then
                local angleRad = math.rad(State.boat.angle)
                local cosA = math.cos(angleRad)
                local sinA = math.sin(angleRad)
                local sampleDist = 12  -- close to boat size boundary
                
                -- Probe 8 directions at distance 12
                local nearWall = false
                local minDist = 999
                for a = 0, 7 do
                    local ang = a * (math.pi / 4)
                    local sx = bx + math.cos(ang) * sampleDist
                    local sy = by + math.sin(ang) * sampleDist
                    if sx < 0 or sx > Config.PlayArea.width or sy < 0 or sy > Config.PlayArea.height or
                       (levelCollisionImage:sample(sx, sy) ~= gfx.kColorClear) then
                        nearWall = true
                        minDist = sampleDist
                    end
                end
                
                if nearWall then
                    if not Telemetry.inNearMissRange then
                        Telemetry.inNearMissRange = true
                        Telemetry.minNearMissDist = minDist
                    else
                        if minDist < Telemetry.minNearMissDist then Telemetry.minNearMissDist = minDist end
                    end
                else
                    if Telemetry.inNearMissRange then
                        -- We were near, now we are safe without crashing! Log near miss!
                        Telemetry.nearMissesCount = Telemetry.nearMissesCount + 1
                        local runTimeStr = formatTime(Telemetry.runFrames)
                        print(string.format("[NEAR_MISS] time_in_run=%s speed=%.2f distance_to_wall=%.1f", 
                            runTimeStr, speed, Telemetry.minNearMissDist))
                        Telemetry.inNearMissRange = false
                    end
                end
            else
                Telemetry.inNearMissRange = false
            end
        end
    else
        -- We are in a menu screen
        Telemetry.menuFrames = Telemetry.menuFrames + 1
    end
end
