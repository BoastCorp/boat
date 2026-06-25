import "state"
import "config"

function drawOffScreenFishIndicators()
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

function drawBoostIndicator()
    local boat = State.boat
    local actualCooldown = getActualBoostCooldown()
    local cooldownMax = math.floor(actualCooldown * Config.RefreshRate)
    
    -- Always draw the background circle as a "recharging" UI element
    local margin = 20
    local x = 400 - margin
    local y = 240 - margin
    local radius = 12
    
    gfx.setLineWidth(2)
    
    if boat.boostCooldownFrames > 0 and cooldownMax > 0 then
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

function drawDockScreen()
    gfx.clear(gfx.kColorBlack)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    if dockImage then
        dockImage:draw(0, 0)
    else
        gfx.drawText("DOCK (Image missing)", 100, 100)
    end

    -- Draw simple menu instructions at the bottom
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.setFont(roobert11)
    gfx.drawText("▲ Play    ▼ Level    ◀ Upgrades    ▶ Soundtrack", 60, 222)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setFont(nil)
end

function drawLevelSelectScreen()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Header
    gfx.setFont(roobert24)
    gfx.drawText("SELECT LEVEL", 120, 15)
    gfx.drawLine(0, 48, 400, 48)

    -- Level options
    local startY = 70
    local itemHeight = 45
    local width = 260
    local startX = (400 - width) / 2

    for lvl = 1, 2 do
        local y = startY + (lvl - 1) * (itemHeight + 15)
        local isSelected = (State.currentLevel == lvl)

        if isSelected then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(startX, y, width, itemHeight)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(startX, y, width, itemHeight)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        gfx.setFont(roobert24)
        local text = "LEVEL " .. lvl
        local textW = roobert24:getTextWidth(text)
        gfx.drawText(text, startX + (width - textW) / 2, y + 10)
    end

    -- Footer
    gfx.drawLine(0, 210, 400, 210)
    gfx.setFont(roobert11)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.drawText("U/D: Select Level   A/B: Confirm & Back", 95, 218)
    
    gfx.setFont(nil)
end

function drawUpgradeScreen()
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
        local maxLevel = (i == 2 or i == 3) and 12 or (i == 4 and 6 or 24)
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

function drawMusicScreen()
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

function drawDebugMenu()
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
        local maxLevel = (i == 2 or i == 3) and 12 or (i == 4 and 6 or 24)

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

function drawSecretMenu()
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
        { name = "Boost", type = "upgrade", index = 4, max = 6 },
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

