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

local function drawSparks()
    if not State.sparks then
        State.sparks = {}
        for t = 1, 3 do
            for i = 1, 5 do
                table.insert(State.sparks, {
                    imgIndex = t,
                    x = math.random(0, 400),
                    y = math.random(0, 240),
                    frame = 1,
                    timer = math.random(0, 100),
                    speed = math.random(3, 7)
                })
            end
        end
    end

    local imgs = {spark1Image, spark2Image, spark3Image}
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    for _, s in ipairs(State.sparks) do
        s.timer = s.timer - 1
        if s.timer <= 0 then
            s.frame = s.frame + 1
            s.timer = s.speed
            if s.frame > 4 then
                s.frame = 1
                s.timer = math.random(50, 200)
                s.x = math.random(0, 400)
                s.y = math.random(0, 240)
            end
        end
        
        local img = imgs[s.imgIndex]
        if img and s.frame > 1 then
            local sx = (s.frame - 1) * 20
            img:draw(s.x, s.y, gfx.kImageUnflipped, sx, 0, 20, 20)
        end
    end
end

function drawDockScreen()
    gfx.clear(gfx.kColorBlack)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    local frameDuration = 5 -- 5 frames per animation step at 50 FPS (10 FPS animation)
    State.dockFrameCounter = ((State.dockFrameCounter or 0) + 1) % (44 * frameDuration)
    local step = math.floor(State.dockFrameCounter / frameDuration)
    local cycleStep = step % 44
    local currentFrame = 1
    
    if cycleStep < 40 then
        currentFrame = (cycleStep % 4) + 1
    else
        currentFrame = (cycleStep - 40) + 5
    end
    
    if dockSpriteImage then
        dockSpriteImage:draw(0, 0, gfx.kImageUnflipped, (currentFrame - 1) * 400, 0, 400, 240)
    else
        gfx.drawText("DOCK (Animation Image missing)", 100, 100)
    end

    -- Draw list menu on the left side
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.setColor(gfx.kColorWhite)
    
    local menuItems = {
        { name = "Play", x = 30, y = 50, width = 180, height = 55, isSprite = true, sprite = playSpriteImage },
        { name = "Upgrades", x = 30, y = 110, width = 180, height = 55, isSprite = true, sprite = upgradeSpriteImage },
        { name = "Soundtrack", x = 30, y = 170, width = 180, height = 55, isSprite = true, sprite = tapeSpriteImage }
    }
    
    for i, item in ipairs(menuItems) do
        local isSelected = (i == State.dockMenuIndex)
        if isSelected then
            -- Draw vector triangle pointing right next to selected item, centered vertically
            local arrowX = item.x - 20
            local arrowY = item.y + (item.height / 2) - 5
            gfx.fillTriangle(arrowX, arrowY, arrowX + 8, arrowY + 5, arrowX, arrowY + 10)
        end
        
        if item.isSprite then
            local spriteImg = item.sprite
            if spriteImg then
                local currentFrame = 1
                if isSelected then
                    local frameDuration = 5
                    local step = math.floor(State.dockFrameCounter / frameDuration) % 4
                    currentFrame = step + 1
                end
                gfx.setImageDrawMode(gfx.kDrawModeCopy)
                spriteImg:draw(item.x, item.y, gfx.kImageUnflipped, (currentFrame - 1) * 180, 0, 180, 55)
                gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            else
                gfx.setFont(roobert24)
                gfx.drawText(item.name, item.x, item.y + 15)
            end
        else
            gfx.setFont(roobert24)
            gfx.drawText(item.name, item.x, item.y)
        end
    end

    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setFont(nil)
end


function drawUpgradeScreen()
    gfx.clear(gfx.kColorBlack)
    
    local shapes = {
        { x=33, y=69, w=111, h=137 },
        { x=155, y=56, w=68, h=147 },
        { x=240, y=50, w=96, h=157 },
        { x=342, y=95, w=36, h=105 }
    }
    
    gfx.setColor(gfx.kColorWhite)
    
    local visualToState = {3, 2, 1, 4}
    
    local function getTremble(visualIndex)
        local stateIndex = visualToState[visualIndex]
        local upgrade = State.upgrades[stateIndex]
        if upgrade and upgrade.level == getMaxUpgradeLevel(stateIndex) then
            local ms = playdate.getCurrentTimeMilliseconds()
            local phaseX = (ms * 0.05) + (visualIndex * 2.1)
            local phaseY = (ms * 0.06) + (visualIndex * 3.7)
            local tx, ty = 0, 0
            if math.sin(phaseX) > 0.8 then tx = 1 elseif math.sin(phaseX) < -0.8 then tx = -1 end
            if math.cos(phaseY) > 0.8 then ty = 1 elseif math.cos(phaseY) < -0.8 then ty = -1 end
            return tx, ty
        end
        return 0, 0
    end
    
    for visualIndex = 1, 4 do
        local stateIndex = visualToState[visualIndex]
        local upgrade = State.upgrades[stateIndex]
        
        if upgrade and upgrade.level > 0 then
            local shape = shapes[visualIndex]
            local maxLevel = getMaxUpgradeLevel(stateIndex)
            local percentage = upgrade.level / maxLevel
            local fillHeight = shape.h * percentage
            
            local tx, ty = getTremble(visualIndex)
            
            local pts = {}
            -- Bottom-Left
            table.insert(pts, shape.x + tx)
            table.insert(pts, shape.y + shape.h + ty)

            local resolution = 4
            local time = playdate.getCurrentTimeMilliseconds()
            local phase = time * 0.006
            local amplitude = 3
            local waveLength = 60
            
            local baseY = shape.y + shape.h - fillHeight + ty

            -- Top edge with sine wave
            for px = shape.x, shape.x + shape.w, resolution do
                local waveY = math.sin(((px - shape.x) / waveLength) * math.pi * 2 + phase) * amplitude
                local topY = baseY + waveY
                if topY > shape.y + shape.h + ty then topY = shape.y + shape.h + ty end
                table.insert(pts, px + tx)
                table.insert(pts, topY)
            end

            -- Ensure right edge is exactly hit
            if pts[#pts - 1] - tx < shape.x + shape.w then
                local px = shape.x + shape.w
                local waveY = math.sin(((px - shape.x) / waveLength) * math.pi * 2 + phase) * amplitude
                local topY = baseY + waveY
                if topY > shape.y + shape.h + ty then topY = shape.y + shape.h + ty end
                table.insert(pts, px + tx)
                table.insert(pts, topY)
            end

            -- Bottom-Right
            table.insert(pts, shape.x + shape.w + tx)
            table.insert(pts, shape.y + shape.h + ty)

            gfx.fillPolygon(table.unpack(pts))
        end
    end
    
    -- Draw the animated upgrade sprites on top
    local frameDuration = 5
    State.upgradeFrameCounter = ((State.upgradeFrameCounter or 0) + 1)
    local currentFrame = (math.floor(State.upgradeFrameCounter / frameDuration) % 4) + 1
    local sourceX = (currentFrame - 1) * 400
    
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    local sel = State.selectedUpgrade
    
    local function drawShapeSprite(sprite, index)
        if not sprite then return end
        local drawSourceX = (index == sel) and sourceX or 0
        local tx, ty = getTremble(index)
        sprite:draw(tx, ty, gfx.kImageUnflipped, drawSourceX, 0, 400, 240)
    end
    
    drawShapeSprite(upgradeLineSprite, 1)
    drawShapeSprite(upgradeSpeedSprite, 2)
    drawShapeSprite(upgradeValueSprite, 3)
    drawShapeSprite(upgradeBoostSprite, 4)
    -- Draw text sprites (animate only if selected)
    
    local function drawTextSprite(sprite, index)
        if not sprite then return end
        local drawSourceX = (index == sel) and sourceX or 0
        local tx, ty = getTremble(index)
        sprite:draw(tx, ty, gfx.kImageUnflipped, drawSourceX, 0, 400, 240)
    end
    
    drawTextSprite(upgradeLineTextSprite, 1)
    drawTextSprite(upgradeSpeedTextSprite, 2)
    drawTextSprite(upgradeValueTextSprite, 3)
    drawTextSprite(upgradeBoostTextSprite, 4)
    
    -- Draw costs beneath shapes
    gfx.setFont(roobert11)
    for visualIndex = 1, 4 do
        local stateIndex = visualToState[visualIndex]
        local upgrade = State.upgrades[stateIndex]
        if upgrade then
            local maxLevel = getMaxUpgradeLevel(stateIndex)
            if upgrade.level < maxLevel then
                local shape = shapes[visualIndex]
                local costVal = calculateUpgradeCost(stateIndex, upgrade.level + 1)
                local text = tostring(costVal)
                
                local textW = roobert11:getTextWidth(text)
                local coinW, coinH = 0, 0
                if coinImage then
                    coinW, coinH = coinImage:getSize()
                end
                
                local space = 2
                local totalW = textW + space + coinW
                
                local tx, ty = getTremble(visualIndex)
                local textX = shape.x + (shape.w / 2) - (totalW / 2) + tx
                local textY = 212 + ty  -- Fixed baseline for all costs
                
                gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
                gfx.drawText(text, textX, textY)
                
                if coinImage then
                    local coinY = textY + (roobert11:getHeight() - coinH) / 2
                    gfx.setImageDrawMode(gfx.kDrawModeCopy)
                    coinImage:draw(textX + textW + space, coinY)
                end
            end
        end
    end
    gfx.setFont(nil)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function drawMusicScreen()
    gfx.clear(gfx.kColorBlack)
    
    drawSparks()
    
    if spark4Image and State.spark4StartTime then
        local ms = playdate.getCurrentTimeMilliseconds()
        local animTime = ms - State.spark4StartTime
        local frameDuration = 70 -- 70ms per frame for fast animation
        local currentFrame = math.floor(animTime / frameDuration) + 1
        
        if currentFrame <= 7 then
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
            local sourceX = (currentFrame - 1) * 400
            spark4Image:draw(0, 0, gfx.kImageUnflipped, sourceX, 0, 400, 240)
        else
            State.spark4StartTime = nil -- end animation
        end
    end
    
    gfx.setColor(gfx.kColorWhite)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)

    -- 3x2 Grid (3 columns, 2 rows)
    local colPadding = 30
    local rowPadding = 10
    local tapeW, tapeH = 75, 74
    local gridWidth = (3 * tapeW) + (2 * colPadding)
    local startX = (400 - gridWidth) / 2
    local startY = 40

    for i = 1, 6 do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = startX + col * (tapeW + colPadding)
        local y = startY + row * (tapeH + rowPadding)

        local isCursor = (i == State.musicSelectionIndex)
        local isSelected = (i == State.selectedMusic)
        
        local floatY = 0
        if isCursor then
            local ms = playdate.getCurrentTimeMilliseconds()
            local period = 1200 -- ms for a full up-and-down cycle
            local t = (ms % period) / (period / 2) -- goes 0 to 2
            if t > 1 then t = 2 - t end -- ping pong 0 to 1 to 0
            floatY = (t - 0.5) * 10 -- range from -5 to 5
        end
        
        local drawY = y + floatY

        -- Draw Tape (Full size 75x74)
        if tapeImage then
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
            tapeImage:draw(x, drawY)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.drawRect(x, drawY, tapeW, tapeH)
            gfx.drawText("TAPE " .. i, x + 5, drawY + 25)
        end

        -- "Playing" or "Active" indicator
        if isSelected then
            gfx.fillCircleAtPoint(x + tapeW - 8, drawY + 8, 5)
        end
    end
    
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
        local maxLevel = getMaxUpgradeLevel(i)

        if i == State.debugSelectedUpgrade then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(0, y - 1, 400, 14)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        local displayLevel = upgrade.level
        local displayMaxLevel = maxLevel
        if i > 4 then
            local prevMax = getMaxUpgradeLevel(i - 4)
            displayLevel = upgrade.level + prevMax
            displayMaxLevel = maxLevel + prevMax
        end
        local levelStr = "L" .. displayLevel .. "/" .. displayMaxLevel
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
    local fishValue = 1 + getEffectiveUpgradeLevel(1)
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
        { name = "Value", type = "upgrade", index = 1, max = 10 },
        { name = "Speed", type = "upgrade", index = 2, max = 10 },
        { name = "Line",  type = "upgrade", index = 3, max = 10 },
        { name = "Boost", type = "upgrade", index = 4, max = 3 },
        { name = "Fish 1", type = "fishSize", index = 1, max = 100 },
        { name = "Fish 2", type = "fishSize", index = 2, max = 100 },
        { name = "Fish 3", type = "fishSize", index = 3, max = 100 },
        { name = "Fish 4", type = "fishSize", index = 4, max = 100 },
        { name = "Fish 5", type = "fishSize", index = 5, max = 100 },
        { name = "Fish 6", type = "fishSize", index = 6, max = 100 },
        { name = "Fish 7", type = "fishSize", index = 7, max = 100 },
        { name = "Fish 8", type = "fishSize", index = 8, max = 100 },
        { name = "W-Size",  type = "waveScale", value = State.waveScale },
        { name = "W-Anim",  type = "waveAnim", value = State.waveAnimSpeed },
        { name = "W-Count", type = "waveCount", value = State.waveCount },
        { name = "F-Count", type = "fishCount", value = State.fishCount },
        { name = "F-Speed", type = "fishSpeed", value = State.fishSpeedMult },
        { name = "B-Cooldown", type = "boostCooldown", value = State.boostCooldownDuration },
        { name = "Markers", type = "toggle", key = "showFishMarkers" },
        { name = "Inf-Money", type = "toggle", key = "infiniteMoney" },
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

function updateFloatingTexts()
    for i = #State.floatingTexts, 1, -1 do
        local ft = State.floatingTexts[i]
        ft.timer = ft.timer - 1
        if ft.timer <= 0 then
            table.remove(State.floatingTexts, i)
        else
            ft.yOffset = ft.yOffset - 0.6
        end
    end
end

function drawFloatingTexts()
    local activeFont = roobert8 or roobert11
    gfx.setFont(activeFont)
    for _, ft in ipairs(State.floatingTexts) do
        if ft.showCoin and coinImage then
            local textW = activeFont:getTextWidth(ft.text)
            local coinW, coinH = coinImage:getSize()
            local space = 4
            local totalW = textW + space + coinW
            local x = 200 - (totalW / 2)
            local y = 120 + ft.yOffset
            
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(ft.text, x, y + 1)
            
            local coinY = y + (activeFont:getHeight() - coinH) / 2
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
            coinImage:draw(x + textW + space, coinY)
        else
            local textW = activeFont:getTextWidth(ft.text)
            local x = 200 - (textW / 2)
            local y = 120 + ft.yOffset
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(ft.text, x, y + 1)
        end
    end
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setFont(nil)
end

