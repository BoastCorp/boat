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
        speed = 2.0,
        rotationSpeed = 5,
        size = { w = 80, l = 80 }
    },
    Fish = {
        count = 5,
        spawnRadius = 80,
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
        velocity_x = 0,  -- Momentum in world space
        velocity_y = 0,
    },
    wake = {},
    fish = {},
    score = 0,
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
local boatSprites = gfx.imagetable.new('images/boat/boat')
local shadowSprites = gfx.imagetable.new('images/boat/shadow')

-- Spawn fish at static positions around origin
for i = 1, Config.Fish.count do
    local angle = (i / Config.Fish.count) * 2 * math.pi
    local dist = 40 + math.random() * Config.Fish.spawnRadius
    State.fish[i] = {
        x = math.cos(angle) * dist,
        y = math.sin(angle) * dist,
        alive = true,
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

    -- Crank steers the boat
    local crankChange = playdate.getCrankChange()
    boat.angle = boat.angle + crankChange

    -- Target velocity based on current angle (where boat wants to go)
    local angle_rad = math.rad(boat.angle - 90)
    local target_vx = math.cos(angle_rad) * Config.Boat.speed
    local target_vy = math.sin(angle_rad) * Config.Boat.speed

    -- Smoothly lerp velocity toward target (momentum/inertia with drift)
    -- Slip factor scaled relative to boat sprite size (80px) vs original polygon (18px)
    -- Larger boat = more drift mass = lower slip value
    local baseSlip = 0.125
    local slip = baseSlip * (18 / Config.Boat.size.l)
    boat.velocity_x = boat.velocity_x + (target_vx - boat.velocity_x) * slip
    boat.velocity_y = boat.velocity_y + (target_vy - boat.velocity_y) * slip

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

    local sternOffset = Config.Boat.size.l / 2
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
                        State.score = State.score + 1
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

    -- Draw shadow sprite (offset by 7 pixels)
    if shadowSprites and shadowSprites[frameIndex] then
        shadowSprites[frameIndex]:drawAnchored(x + 7, y + 7, 0.5, 0.5)
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

    -- Draw fish (stationary circles)
    gfx.setColor(gfx.kColorBlack)
    for _, f in ipairs(State.fish) do
        if f.alive then
            local fx, fy = project(f.x, f.y)
            gfx.fillCircleAtPoint(fx, fy, Config.Fish.size)
        end
    end

    -- Draw boat (includes shadow with dithering) at screen center
    local boat_screen_x, boat_screen_y = project(State.boat.x, State.boat.y)
    drawBoat(boat_screen_x, boat_screen_y, State.boat.angle)

    -- Score
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.drawText("Score: " .. State.score, 4, 4)
end

-- ---------------------------------------------------------
-- Main Loop
-- ---------------------------------------------------------
function playdate.update()
    updateInput()

    waterFrameTime = waterFrameTime + 1
    gfx.clear()
    drawContent()
end
