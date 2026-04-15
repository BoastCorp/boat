import 'title'

-- Setting up consts
local pd <const> = playdate
local gfx <const> = pd.graphics
local smp <const> = pd.sound.sampleplayer
local fle <const> = pd.sound.fileplayer
local geo <const> = pd.geometry
local text <const> = gfx.getLocalizedText

class('theater').extends(gfx.sprite) -- Create the scene's class
function theater:init(...)
	theater.super.init(self)
	local args = {...} -- Arguments passed in through the scene management will arrive here
	show_crank = false -- Should the crank indicator be shown?
	gfx.sprite.setAlwaysRedraw(false) -- Should this scene redraw the sprites constantly?

	function pd.gameWillPause() -- When the game's paused...
		local menu = pd.getSystemMenu()
		menu:removeAllMenuItems()
		setpauseimage(50)
		if not vars.transitioning then
			menu:addMenuItem(text('backtotitle'), function()
				if not vars.transitioning then
					self:leave()
				end
			end)
		end
	end

	assets = { -- All assets go here. Images, sounds, fonts, etc.
		kapel = gfx.font.new('fonts/kapel'),
		pedallica = gfx.font.new('fonts/pedallica'),
		kapel_doubleup = gfx.font.new('fonts/kapel_doubleup'),
		image_ticker = gfx.image.new(800, 20, gfx.kColorBlack),
		image_wave = gfx.image.new('images/ui/wave'),
		image_wave_composite = gfx.image.new(464, 280),
		image_back = makebutton(text('back'), "small2"),
		image_popup_small = gfx.image.new('images/ui/popup_small'),
		sfx_bonk = smp.new('audio/sfx/bonk'),
		sfx_menu = smp.new('audio/sfx/menu'),
		sfx_proceed = smp.new('audio/sfx/proceed'),
		cutscene1 = gfx.image.new('images/ui/cutscene1'),
		cutscene2 = gfx.image.new('images/ui/cutscene2'),
		cutscene3 = gfx.image.new('images/ui/cutscene3'),
		cutscene4 = gfx.image.new('images/ui/cutscene4'),
		cutscene5 = gfx.image.new('images/ui/cutscene5'),
		cutscene6 = gfx.image.new('images/ui/cutscene6'),
		cutscene7 = gfx.image.new('images/ui/cutscene7'),
		cutscene8 = gfx.image.new('images/ui/cutscene8'),
		cutscene9 = gfx.image.new('images/ui/cutscene9'),
		cutscene10 = gfx.image.new('images/ui/cutscene10'),
	}
	assets.sfx_bonk:setVolume(save.vol_sfx/5)
	assets.sfx_menu:setVolume(save.vol_sfx/5)
	assets.sfx_proceed:setVolume(save.vol_sfx/5)

	-- Writing in the image for the wave banner along the bottom
	gfx.pushContext(assets.image_wave_composite)
		assets.image_wave:drawTiled(0, 0, 464, 280)
	gfx.popContext()

	vars = { -- All variables go here. Args passed in from earlier, scene variables, etc.
		selection = args[1] or 1,
		transitioning = true,
		anim_wave_x = pd.timer.new(5000, 0, -58),
		anim_wave_y = pd.timer.new(1000, -30, 185, pd.easingFunctions.outCubic), -- Send the wave down from above
	}
	vars.theaterHandlers = {
		AButtonDown = function()
			scenemanager:transitionsceneoneway(cutscene, vars.selection, true)
			assets.sfx_proceed:play()
			fademusic()
			gfx.sprite.redrawBackground()
		end,

		upButtonDown = function()
			self:newselection(false)
		end,

		downButtonDown = function()
			self:newselection(true)
		end,

		BButtonDown = function()
			if not vars.transitioning then
				self:leave()
			end
		end
	}

	pd.timer.performAfterDelay(1000, function() -- After the wave's done animating inward...
		vars.transitioning = false -- Start accepting button presses to go back.
		vars.anim_wave_y:resetnew(5000, 185, 195, pd.easingFunctions.inOutCubic) -- Set the wave's idle animation,
		vars.anim_wave_y.repeats = true -- make it repeat forever,
		vars.anim_wave_y.reverses = true -- and make it loop!
		pd.inputHandlers.push(vars.theaterHandlers) -- Wait to push the input handlers, so you can't fuck with shit before you have a chance to read it.
	end)

	vars.textwidth = assets.kapel_doubleup:getTextWidth(text('theater')) + 10
	-- Writing in the image for the "Options" header ticker
	gfx.pushContext(assets.image_ticker)
		gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		assets.kapel_doubleup:drawText(text('theater'), vars.textwidth * 1, -3)
		assets.kapel_doubleup:drawText(text('theater'), vars.textwidth * 2, -3)
		assets.kapel_doubleup:drawText(text('theater'), vars.textwidth * 3, -3)
		assets.kapel_doubleup:drawText(text('theater'), vars.textwidth * 4, -3)
		assets.kapel_doubleup:drawText(text('theater'), vars.textwidth * 5, -3)
		assets.kapel_doubleup:drawText(text('theater'), vars.textwidth * 6, -3)
		assets.kapel_doubleup:drawText(text('theater'), vars.textwidth * 7, -3)
	gfx.popContext()

	vars.anim_ticker = pd.timer.new(2000, -vars.textwidth, (-vars.textwidth * 2) + 1)
	vars.anim_ticker.repeats = true
	vars.anim_wave_x.repeats = true
	vars.anim_wave_y.discardOnCompletion = false

	gfx.sprite.setBackgroundDrawingCallback(function(x, y, width, height) -- Background drawing
		gfx.image.new(400, 240, gfx.kColorWhite):draw(0, 0)
		assets.image_popup_small:draw(192, 26)
		gfx.fillRect(0, 5 + 15 * vars.selection + 10, 5, 15)

		assets.pedallica:drawText(text('cutscene1'), 10, 30)
		assets.pedallica:drawText(text('cutscene2'), 10, 45)
		assets.pedallica:drawText(text('cutscene3'), 10, 60)
		assets.pedallica:drawText(text('cutscene4'), 10, 75)
		assets.pedallica:drawText(text('cutscene5'), 10, 90)
		assets.pedallica:drawText(text('cutscene6'), 10, 105)
		assets.pedallica:drawText(text('cutscene7'), 10, 120)
		assets.pedallica:drawText(text('cutscene8'), 10, 135)
		assets.pedallica:drawText(text('cutscene9'), 10, 150)
		assets.pedallica:drawText(text('cutscene10'), 10, 165)

		assets.pedallica:drawText(text('watchqr'), 213, 48)
		assets['cutscene' .. vars.selection]:draw(255, 95)
	end)

	class('theater_ticker', _, classes).extends(gfx.sprite)
	function classes.theater_ticker:init()
		classes.theater_ticker.super.init(self)
		self:setImage(assets.image_ticker)
		self:setCenter(0, 0)
		self:setZIndex(1)
		self:add()
	end
	function classes.theater_ticker:update()
		self:moveTo(vars.anim_ticker.value, 0)
	end

	class('theater_wave', _, classes).extends(gfx.sprite)
	function classes.theater_wave:init()
		classes.theater_wave.super.init(self)
		self:setSize(464, 280)
		self:setCenter(0, 0)
		self:setZIndex(2)
		self:moveTo(0, 185)
		self:add()
	end
	function classes.theater_wave:update()
		self:moveTo(0, vars.anim_wave_y.value)
	end
	function classes.theater_wave:draw()
		assets.image_wave_composite:draw(vars.anim_wave_x.value, 0)
	end

	class('theater_back', _, classes).extends(gfx.sprite)
	function classes.theater_back:init()
		classes.theater_back.super.init(self)
		self:setCenter(0, 0)
		self:setZIndex(3)
		self:setImage(assets.image_back)
		self:moveTo(295, 210)
		self:add()
	end
	function classes.theater_back:update()
		self:moveTo(295, (vars.anim_wave_y.value*1.1))
	end

	-- Set the sprites
	sprites.ticker = classes.theater_ticker()
	sprites.wave = classes.theater_wave()
	sprites.back = classes.theater_back()
	self:add()

	newmusic('audio/music/title', true, 1.1) -- Adding new music
end

-- Select a new stage using the arrow keys. dir is a boolean — left is false, right is true
function theater:newselection(dir, num)
	vars.old_selection = vars.selection
	if dir then
		vars.selection = math.clamp(vars.selection + (num or 1), 1, 10)
	else
		vars.selection = math.clamp(vars.selection - (num or 1), 1, 10)
	end
	-- If this is true, then that means we've reached an end and nothing has changed.
	if vars.old_selection == vars.selection then
		assets.sfx_bonk:play()
		shakies_y()
	else
		assets.sfx_menu:play()
		gfx.sprite.redrawBackground()
	end
end

function theater:leave() -- Leave and move back to the title screen
	pd.inputHandlers.pop() -- Pop the handlers, so you can't change anything as you're leaving.
	vars.transitioning = true -- Make sure you don't accept any more button presses at this time
	vars.anim_wave_y:resetnew(1000, sprites.wave.y, -40, pd.easingFunctions.inBack) -- Send the wave back up to transition smoothly
	pd.timer.performAfterDelay(1200, function() -- After that animation's done...
		scenemanager:switchscene(title, title_memorize) -- Switch back to the title!
	end)
end

function theater:update()
	if not scenemanager.transitioning then
		local ticks = pd.getCrankTicks(7)
		if not vars.transitioning then
			if ticks < 0 then
				self:newselection(false, -ticks)
			elseif ticks > 0 then
				self:newselection(true, ticks)
			end
		end
	end
end