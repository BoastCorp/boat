import 'title'

-- Setting up consts
local pd <const> = playdate
local gfx <const> = pd.graphics
local smp <const> = pd.sound.sampleplayer
local fle <const> = pd.sound.fileplayer
local text <const> = gfx.getLocalizedText
local floor <const> = math.floor

class('speedrun').extends(gfx.sprite) -- Create the scene's class
function speedrun:init(...)
    speedrun.super.init(self)
    local args = {...} -- Arguments passed in through the scene management will arrive here
    show_crank = false -- Should the crank indicator be shown?
    gfx.sprite.setAlwaysRedraw(true) -- Should this scene redraw the sprites constantly?

    function pd.gameWillPause() -- When the game's paused...
        local menu = pd.getSystemMenu()
        menu:removeAllMenuItems()
        setpauseimage(100)
    end

    assets = { -- All assets go here. Images, sounds, fonts, etc.
        kapel = gfx.font.new('fonts/kapel'),
		pedallica = gfx.font.new('fonts/pedallica'),
        times_new_rally = gfx.font.new('fonts/times_new_rally'),
        double_time = gfx.font.new('fonts/double_time'),
        kapel_doubleup = gfx.font.new('fonts/kapel_doubleup'),
        sfx_proceed = smp.new('audio/sfx/proceed'),
		ok = makebutton(text('ok'), "big")
    }
    assets.sfx_proceed:setVolume(save.vol_sfx/5)

    vars = { -- All variables go here. Args passed in from earlier, scene variables, etc.
		newbest = false,
		fade_timer = pd.timer.new(1000, 0.5, 1),
		poly = pd.geometry.polygon.new(0, 65, 400, 85, 400, 155, 0, 135, 0, 65),
    }
    vars.resultsHandlers = {
        AButtonDown = function()
			fademusic()
			assets.sfx_proceed:play()
			scenemanager:transitionsceneoneway(title, title_memorize)
        end,
    }
    pd.inputHandlers.push(vars.resultsHandlers)

	if speedrun_time < save.speedrun_time or save.speedrun_time == 0 then
		save.speedrun_time = speedrun_time
		vars.newbest = true
	end

	vars.fade_timer.reverses = true
	vars.fade_timer.repeats = true

	self:timecalc(speedrun_time)
	gfx.setFont(assets.kapel_doubleup)

	assets.runcomplete = gfx.imageWithText(text('speedruncomplete'), 400, 240)

    gfx.sprite.setBackgroundDrawingCallback(function(x, y, width, height) -- Background drawing
		gfx.image.new(400, 240, gfx.kColorWhite):draw(0, 0)
		assets.runcomplete:drawScaled(10, 2, 2)
		gfx.fillPolygon(vars.poly)
		gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		assets.kapel_doubleup:drawTextAligned(text('finaltime'), 200, 80, kTextAlignment.center)
		assets.double_time:drawTextAligned(vars.mins .. ':' .. vars.secs .. '.' .. vars.mils, 200, 105, kTextAlignment.center)
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
		gfx.setDitherPattern(vars.fade_timer.value, gfx.image.kDitherTypeBayer8x8)
		gfx.fillRect(57, 104, 285, 33)
		gfx.setColor(gfx.kColorBlack)
		if vars.newbest then
			assets.pedallica:drawTextAligned(text('speedrunnewbest'), 200, 160, kTextAlignment.center)
		end
		assets.ok:drawAnchored(200, 210, 0.5, 0.5)
    end)

	self:sendscores()
	newmusic('audio/sfx/win')
	speedrun_on = false
	speedrun_timer = false
	achievements.grant('speedrun')
	savegame() -- Save the game! This is put last so "Sending score..." takes precedence over "Saving..." corner UI
    self:add()
end

-- This function takes a score number as input, and spits out the proper time in minutes, seconds, and milliseconds
function speedrun:timecalc(num)
	num = floor(num)
	vars.mins = floor((num/30) / 60)
	vars.secs = floor((num/30) - vars.mins * 60)
	vars.mils = floor((num/30)*99 - vars.mins * 5940 - vars.secs * 99)
	if vars.secs < 10 then vars.secs = '0' .. vars.secs end
	if vars.mils < 10 then vars.mils = '0' .. vars.mils end
end

function speedrun:sendscores()
    if playtest or demo or pd.metadata.bundleID ~= "wtf.rae.rowbotrally" then return end
    corner('sendscore')
	if not save.absolute then
		if perf then
			pd.scoreboards.addScore(speedrun, speedrun_time, function(status, result)
				if status.code ~= "OK" and not sending_failed then
					makepopup(text('whoops'), text('popup_leaderboard_failed'), text('ok'), false)
					sending_failed = true
				else
					sending_failed = false
				end
				speedrun_time = 0
			end)
		else
			pd.scoreboards.addScore(speedrun, speedrun_time, function(status, result)
				if status.code ~= "OK" and not sending_failed then
					makepopup(text('whoops'), text('popup_leaderboard_failed'), text('ok'), false)
					sending_failed = true
				else
					sending_failed = false
					pd.scoreboards.addScore('racetime', math.floor(save.total_racetime), function(status)
						pd.scoreboards.addScore('crashes', save.total_crashes, function(status)
							pd.scoreboards.addScore('degreescranked', math.floor(save.total_degrees_cranked), function(status)
							end)
						end)
					end)
				end
				speedrun_time = 0
			end)
		end
	else
		pd.scoreboards.addScore('racetime', math.floor(save.total_racetime), function(status)
			pd.scoreboards.addScore('crashes', save.total_crashes, function(status)
				pd.scoreboards.addScore('degreescranked', math.floor(save.total_degrees_cranked), function(status)
				end)
			end)
		end)
	end
end