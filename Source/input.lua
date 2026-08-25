import "state"

function handleInput()
    if State.transition and State.transition.active then return end
    
    -- 1. Global / Secret Menu Toggle
    if (playdate.buttonJustPressed(playdate.kButtonA) and playdate.buttonIsPressed(playdate.kButtonB)) or
       (playdate.buttonJustPressed(playdate.kButtonB) and playdate.buttonIsPressed(playdate.kButtonA)) then
        startTransition("secret_menu")
        return
    end

    -- 2. Debug Menu Toggle
    if playdate.buttonJustPressed(playdate.kButtonMenu) then
        if playdate.buttonIsPressed(playdate.kButtonA) then
            startTransition("debug")
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

    -- 3. Screen-Specific Input
    if State.currentScreen == "game" then
        handleGameInput()
    elseif State.currentScreen == "dock" then
        handleDockInput()
    elseif State.currentScreen == "upgrade" then
        handleUpgradeInput()
    elseif State.currentScreen == "music" then
        handleMusicInput()
    elseif State.currentScreen == "secret_menu" then
        handleSecretMenuInput()
    elseif State.currentScreen == "debug" then
        handleDebugMenuInput()
    end
end

function handleGameInput()
    if State.isPaused then
        if playdate.buttonJustPressed(playdate.kButtonA) then
            local moneyEarned = State.hold * (1 + getEffectiveUpgradeLevel(1))
            Telemetry.logReturnDock(State.hold, moneyEarned)
            State.isPaused = false
            startTransition("dock")
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            startTransition("game", function()
                resetRound()
            end)
        end
        return
    end

    -- Boost
    if playdate.buttonJustPressed(playdate.kButtonUp) and State.boat.boostFrames <= 0 and State.boat.boostCooldownFrames <= 0 then
        State.boat.boostSpeed = 11.0
        State.boat.boostFrames = 60
        State.boat.boostCooldownFrames = math.floor(getActualBoostCooldown() * Config.RefreshRate)
        State.boat.moveAngle = State.boat.angle
        Telemetry.logBoost()
    end

    -- Steering via Crank
    local crankChange = playdate.getCrankChange()
    State.boat.angle = State.boat.angle + crankChange
end

function handleDockInput()
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        if State.dockMenuIndex > 1 then
            State.dockMenuIndex = State.dockMenuIndex - 1
        else
            State.dockMenuIndex = 3
        end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        if State.dockMenuIndex < 3 then
            State.dockMenuIndex = State.dockMenuIndex + 1
        else
            State.dockMenuIndex = 1
        end
    elseif playdate.buttonJustPressed(playdate.kButtonA) then
        if State.dockMenuIndex == 1 then
            resetRound()
            startTransition("game")
        elseif State.dockMenuIndex == 2 then
            startTransition("upgrade")
        elseif State.dockMenuIndex == 3 then
            startTransition("music")
        end
    end
end

function handleUpgradeInput()
    if playdate.buttonJustPressed(playdate.kButtonB) then
        startTransition("dock")
    else
        local sel = State.selectedUpgrade
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            if sel > 1 then State.selectedUpgrade = sel - 1 end
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            if sel < 4 then State.selectedUpgrade = sel + 1 end
        end

        sel = State.selectedUpgrade
        if playdate.buttonJustPressed(playdate.kButtonA) then
            local visualToState = {3, 2, 1, 4}
            local stateIdx = visualToState[sel]
            
            local nextLevel = State.upgrades[stateIdx].level + 1
            local maxLevel = getMaxUpgradeLevel(stateIdx)
            if nextLevel <= maxLevel then
                local cost = calculateUpgradeCost(stateIdx, nextLevel)
                if State.money >= cost then
                    State.money = State.money - cost
                    State.upgrades[stateIdx].level = nextLevel
                    Telemetry.logUpgrade(State.upgrades[stateIdx].name, nextLevel, cost, State.money)
                end
            end
        end
    end
end

function handleMusicInput()
    if playdate.buttonJustPressed(playdate.kButtonB) then
        startTransition("dock")
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
            State.spark4StartTime = playdate.getCurrentTimeMilliseconds()
        end
    end
end

function handleSecretMenuInput()
    local numItems = 20
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        State.secretMenuIndex = math.max(1, State.secretMenuIndex - 1)
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        State.secretMenuIndex = math.min(numItems, State.secretMenuIndex + 1)
    end

    local idx = State.secretMenuIndex
    if idx <= 4 then -- Upgrades
        local uIdx = idx
        local maxLevel = (uIdx == 4) and 3 or 10
        local minLevel = (uIdx == 4) and 0 or -maxLevel
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.upgrades[uIdx].level = math.max(minLevel, State.upgrades[uIdx].level - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.upgrades[uIdx].level = math.min(maxLevel, State.upgrades[uIdx].level + 1)
        end
    elseif idx >= 5 and idx <= 12 then -- Fish Sizes 1-8
        local sIdx = idx - 4
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.fishSizes[sIdx] = math.max(1, State.fishSizes[sIdx] - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.fishSizes[sIdx] = math.min(100, State.fishSizes[sIdx] + 1)
        end
    elseif idx == 13 then -- Wave Size
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.waveScale = math.max(0.1, State.waveScale - 0.1)
            preScaleWaves()
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.waveScale = math.min(2.0, State.waveScale + 0.1)
            preScaleWaves()
        end
    elseif idx == 14 then -- Wave Anim
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.waveAnimSpeed = math.min(10, State.waveAnimSpeed + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.waveAnimSpeed = math.max(1, State.waveAnimSpeed - 1)
        end
    elseif idx == 15 then -- Wave Count
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.waveCount = math.max(0, State.waveCount - 10)
            initWaves()
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.waveCount = math.min(300, State.waveCount + 10)
            initWaves()
        end
    elseif idx == 16 then -- Fish Count
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.fishCount = math.max(1, State.fishCount - 1)
            spawnFish()
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.fishCount = math.min(50, State.fishCount + 1)
            spawnFish()
        end
    elseif idx == 17 then -- Fish Speed
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.fishSpeedMult = math.max(0.1, State.fishSpeedMult - 0.1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.fishSpeedMult = math.min(5.0, State.fishSpeedMult + 0.1)
        end
    elseif idx == 18 then -- Boost CD
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            State.boostCooldownDuration = math.max(0.0, State.boostCooldownDuration - 0.1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            State.boostCooldownDuration = math.min(10.0, State.boostCooldownDuration + 0.1)
        end
    elseif idx == 19 then -- Markers
        if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
            State.showFishMarkers = not State.showFishMarkers
        end
    elseif idx == 20 then -- Infinite Money
        if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
            State.infiniteMoney = not State.infiniteMoney
        end
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        resetRound()
        startTransition("game")
    elseif playdate.buttonJustPressed(playdate.kButtonB) then
        startTransition("game")
    end
end

function handleDebugMenuInput()
    local sel = State.debugSelectedUpgrade
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        State.debugSelectedUpgrade = math.max(1, sel - 1)
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        State.debugSelectedUpgrade = math.min(#State.upgrades, sel + 1)
    elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
        State.upgrades[sel].level = math.max(0, State.upgrades[sel].level - 1)
    elseif playdate.buttonJustPressed(playdate.kButtonRight) then
        local maxLevel = getMaxUpgradeLevel(sel)
        State.upgrades[sel].level = math.min(maxLevel, State.upgrades[sel].level + 1)
    elseif playdate.buttonJustPressed(playdate.kButtonA) then
        local nextLevel = State.upgrades[sel].level + 1
        local maxLevel = getMaxUpgradeLevel(sel)
        if nextLevel <= maxLevel then
            local cost = calculateUpgradeCost(sel, nextLevel)
            if State.money >= cost then
                State.money = State.money - cost
                State.upgrades[sel].level = nextLevel
            end
        end
    elseif playdate.buttonJustPressed(playdate.kButtonB) then
        startTransition("game")
    end
end
