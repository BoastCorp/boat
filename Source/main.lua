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
        baseSpeed = 3.5,
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
    boat.currentSpeed = Config.Boat.baseSpeed * dragFactor

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
    if #wake > Config.WakeMaxLength then
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
                -- Catch any fish inside the polygon
                for _, f in ipairs(State.fish) do
                    if f.alive and pointInPolygon(f.x, f.y, poly) then
                        f.alive = false
                        State.money = State.money + 1
                    end
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
end

-- ---------------------------------------------------------
-- Upgrade Screen (Skill Tree)
-- ---------------------------------------------------------
import "CoreLibs/graphics"

local ZOOM_MIN = 0.20
local ZOOM_MAX = 2.0
local ZOOM_THRESHOLD = 0.6
local SCREEN_W = 400
local SCREEN_H = 240
local CENTER_X = SCREEN_W / 2
local CENTER_Y = SCREEN_H / 2
local SPACING = 65

local UpgradeScreen = {
    zoom = 1.0,
    camX = 0,
    camY = 0,
    targetCamX = 0,
    targetCamY = 0,
    selectedNodeId = 1,
    nodes = {},
}

local function addNode(id, xGrid, yGrid, cost)
    UpgradeScreen.nodes[id] = {
        id = id,
        x = xGrid * SPACING,
        y = yGrid * SPACING,
        cost = cost,
        active = false,
        neighbors = {}
    }
end

local function addLink(id1, id2)
    table.insert(UpgradeScreen.nodes[id1].neighbors, id2)
    table.insert(UpgradeScreen.nodes[id2].neighbors, id1)
end

-- Initialize skill tree nodes (from your code)
addNode(1, 0, 0, 0)
UpgradeScreen.nodes[1].active = true

-- Left Grid
addNode(2, 0, -1, 2)
addNode(3, 1, -1, 2)
addNode(4, 2, -1, 6)
addNode(5, 0, -2, 7)
addNode(6, 1, -2, 7)
addNode(7, 2, -2, 18)
addNode(8, 3, -2, 15)
addNode(9,  0, -3, 25)
addNode(10, 1, -3, 30)
addNode(11, 2, -3, 20)
addNode(12, 3, -3, 20)
addNode(13, 4, -3, 40)
addNode(14, 5, -3, 60)
addNode(15, 6, -3, 60)
addNode(16, 7, -3, 80)

-- Top Right Extensions
addNode(17, 4, -4, 50)
addNode(18, 5, -4, 60)
addNode(19, 6, -4, 60)
addNode(20, 7, -4, 60)
addNode(21, 6, -5, 65)
addNode(22, 7, -5, 70)

-- Bottom Right Wall Group
addNode(23, 4, 0, 300)
addNode(24, 4, -1, 350)
addNode(25, 5, 0, 350)
addNode(26, 5, -1, 425)
addNode(27, 5, -2, 475)
addNode(28, 4, 1, 400)
addNode(29, 5, 1, 600)

-- Wire connections
addLink(1, 2); addLink(1, 23)
addLink(2, 3); addLink(3, 4)
addLink(5, 6); addLink(6, 7); addLink(7, 8)
addLink(9, 10); addLink(10, 11); addLink(11, 12); addLink(12, 13)
addLink(13, 14); addLink(14, 15); addLink(15, 16)
addLink(17, 18); addLink(18, 19); addLink(19, 20)
addLink(21, 22)
addLink(23, 25); addLink(28, 29)
addLink(2, 5); addLink(5, 9)
addLink(3, 6); addLink(6, 10)
addLink(4, 7); addLink(7, 11)
addLink(8, 12)
addLink(13, 17); addLink(14, 18)
addLink(15, 19); addLink(19, 21)
addLink(16, 20); addLink(20, 22)
addLink(23, 24); addLink(25, 26); addLink(26, 27)
addLink(23, 28); addLink(25, 29)

local function isNeighborUnlocked(id)
    if id == 1 then return true end
    for _, neighborId in ipairs(UpgradeScreen.nodes[id].neighbors) do
        if UpgradeScreen.nodes[neighborId].active then return true end
    end
    return false
end

local function moveGranular(dir)
    local curr = UpgradeScreen.nodes[UpgradeScreen.selectedNodeId]
    local bestDist = math.huge
    local bestNodeId = nil

    for _, nid in ipairs(curr.neighbors) do
        local n = UpgradeScreen.nodes[nid]
        local dx = n.x - curr.x
        local dy = n.y - curr.y
        local dist = math.abs(dx) + math.abs(dy)

        local valid = false
        if dir == "right" and dx > 0 then valid = true
        elseif dir == "left" and dx < 0 then valid = true
        elseif dir == "down" and dy > 0 then valid = true
        elseif dir == "up" and dy < 0 then valid = true
        end

        if valid and dist < bestDist then
            bestDist = dist
            bestNodeId = nid
        end
    end

    if bestNodeId then UpgradeScreen.selectedNodeId = bestNodeId end
end

local function snapToNearestCenter()
    local bestDist = math.huge
    local bestNodeId = UpgradeScreen.selectedNodeId

    for id, n in pairs(UpgradeScreen.nodes) do
        local dx = n.x - UpgradeScreen.camX
        local dy = n.y - UpgradeScreen.camY
        local dist = dx*dx + dy*dy
        if dist < bestDist then
            bestDist = dist
            bestNodeId = id
        end
    end
    UpgradeScreen.selectedNodeId = bestNodeId
end

local function drawUpgradeScreen()
    gfx.clear(gfx.kColorWhite)

    -- Handle Crank (Zoom)
    local crankChange = playdate.getCrankChange()
    if crankChange ~= 0 then
        UpgradeScreen.zoom = UpgradeScreen.zoom + (crankChange * 0.005)
        if UpgradeScreen.zoom < ZOOM_MIN then UpgradeScreen.zoom = ZOOM_MIN end
        if UpgradeScreen.zoom > ZOOM_MAX then UpgradeScreen.zoom = ZOOM_MAX end
    end

    local isZoomedOut = (UpgradeScreen.zoom <= ZOOM_THRESHOLD)

    -- Input Handling
    if isZoomedOut then
        local panSpeed = 20 / UpgradeScreen.zoom
        if playdate.buttonIsPressed(playdate.kButtonUp) then UpgradeScreen.targetCamY = UpgradeScreen.targetCamY - panSpeed end
        if playdate.buttonIsPressed(playdate.kButtonDown) then UpgradeScreen.targetCamY = UpgradeScreen.targetCamY + panSpeed end
        if playdate.buttonIsPressed(playdate.kButtonLeft) then UpgradeScreen.targetCamX = UpgradeScreen.targetCamX - panSpeed end
        if playdate.buttonIsPressed(playdate.kButtonRight) then UpgradeScreen.targetCamX = UpgradeScreen.targetCamX + panSpeed end

        UpgradeScreen.camX = UpgradeScreen.camX + (UpgradeScreen.targetCamX - UpgradeScreen.camX) * 0.5
        UpgradeScreen.camY = UpgradeScreen.camY + (UpgradeScreen.targetCamY - UpgradeScreen.camY) * 0.5
        snapToNearestCenter()
    else
        if playdate.buttonJustPressed(playdate.kButtonUp) then moveGranular("up") end
        if playdate.buttonJustPressed(playdate.kButtonDown) then moveGranular("down") end
        if playdate.buttonJustPressed(playdate.kButtonLeft) then moveGranular("left") end
        if playdate.buttonJustPressed(playdate.kButtonRight) then moveGranular("right") end

        UpgradeScreen.targetCamX = UpgradeScreen.nodes[UpgradeScreen.selectedNodeId].x
        UpgradeScreen.targetCamY = UpgradeScreen.nodes[UpgradeScreen.selectedNodeId].y
        UpgradeScreen.camX = UpgradeScreen.camX + (UpgradeScreen.targetCamX - UpgradeScreen.camX) * 0.2
        UpgradeScreen.camY = UpgradeScreen.camY + (UpgradeScreen.targetCamY - UpgradeScreen.camY) * 0.2
    end

    -- Draw Links
    gfx.setLineWidth(math.max(1, 2 * UpgradeScreen.zoom))
    for id, node in pairs(UpgradeScreen.nodes) do
        local sx1 = (node.x - UpgradeScreen.camX) * UpgradeScreen.zoom + CENTER_X
        local sy1 = (node.y - UpgradeScreen.camY) * UpgradeScreen.zoom + CENTER_Y
        for _, nId in ipairs(node.neighbors) do
            if nId > id then
                local n2 = UpgradeScreen.nodes[nId]
                local sx2 = (n2.x - UpgradeScreen.camX) * UpgradeScreen.zoom + CENTER_X
                local sy2 = (n2.y - UpgradeScreen.camY) * UpgradeScreen.zoom + CENTER_Y
                gfx.drawLine(sx1, sy1, sx2, sy2)
            end
        end
    end

    -- Draw Nodes
    local nodeRadius = 12 * UpgradeScreen.zoom
    local selRadius = 20 * UpgradeScreen.zoom

    for id, node in pairs(UpgradeScreen.nodes) do
        local sx = (node.x - UpgradeScreen.camX) * UpgradeScreen.zoom + CENTER_X
        local sy = (node.y - UpgradeScreen.camY) * UpgradeScreen.zoom + CENTER_Y

        if UpgradeScreen.zoom > ZOOM_THRESHOLD then
            local labelText = (id == 1) and "START" or "$" .. node.cost
            local textW = gfx.getTextSize(labelText)
            gfx.drawText(labelText, sx - (textW/2), sy - (24 * UpgradeScreen.zoom))
        end

        if id == UpgradeScreen.selectedNodeId then
            gfx.setLineWidth(math.max(2, 3 * UpgradeScreen.zoom))
            gfx.drawCircleAtPoint(sx, sy, selRadius)
        end

        gfx.setLineWidth(math.max(1, 2 * UpgradeScreen.zoom))

        if node.active then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillCircleAtPoint(sx, sy, nodeRadius)
        else
            gfx.setColor(gfx.kColorWhite)
            gfx.fillCircleAtPoint(sx, sy, nodeRadius)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawCircleAtPoint(sx, sy, nodeRadius)
        end
    end

    -- Draw UI Dashboard
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, 0, 400, 40)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, 40, 400, 40)

    gfx.setFont(roobert11)
    gfx.drawText("Wallet: $" .. State.money, 5, 5)

    local selNode = UpgradeScreen.nodes[UpgradeScreen.selectedNodeId]
    local costText = selNode.active and "OWNED" or "$" .. selNode.cost
    gfx.drawText("Cost: " .. costText, 5, 22)

    gfx.drawText("B: CONTINUE   A: SELECT", 100, 220)
    gfx.setFont(nil)
end

-- ---------------------------------------------------------
-- Main Loop
-- ---------------------------------------------------------
function playdate.update()
    if State.currentScreen == "game" then
        -- GAME SCREEN LOGIC
        -- Only update input and physics if not paused
        if not State.isPaused then
            updateInput()
        end

        -- Always increment round time
        State.roundTime = State.roundTime + 1

        -- Check if round is over
        if State.roundTime >= State.roundDuration then
            State.isPaused = true
        end

        -- Handle pause menu input (B to continue, A to upgrade)
        if State.isPaused then
            if playdate.buttonJustPressed(playdate.kButtonB) then
                -- Reset round: clear wake, respawn fish, reset boat position
                State.roundTime = 0
                State.wake = {}
                State.boat.x = 0
                State.boat.y = 0
                State.boat.angle = 0
                State.boat.moveAngle = 0
                State.boat.currentSpeed = 0
                State.boat.velocity_x = 0
                State.boat.velocity_y = 0
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
                State.isPaused = false
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- Switch to upgrade screen
                State.currentScreen = "upgrade"
            end
        end

        waterFrameTime = waterFrameTime + 1
        gfx.clear()
        drawContent()

    elseif State.currentScreen == "upgrade" then
        -- UPGRADE SCREEN LOGIC
        drawUpgradeScreen()

        -- Handle upgrade screen input
        if playdate.buttonJustPressed(playdate.kButtonB) then
            -- Return to game and start new round
            State.currentScreen = "game"
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
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- Select skill (placeholder for now)
        end
    end
end
