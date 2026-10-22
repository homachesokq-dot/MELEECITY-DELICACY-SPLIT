if not CLIENT then return end

surface.CreateFont("HG_LobotomyIntro", {
	font = "Times New Roman",
	size = ScreenScale(42),
	weight = 700,
	antialias = true
})

surface.CreateFont("HG_LobotomyPhrase", {
	font = "Times New Roman",
	size = ScreenScale(28),
	weight = 700,
	antialias = true
})

surface.CreateFont("HG_LobotomyEmpty", {
	font = "Times New Roman",
	size = ScreenScale(46),
	weight = 700,
	antialias = true
})

local MAX_MISTAKES = 3
local KEY_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local active = false
local introWord = ""
local phrase = ""
local phraseKey = ""
local typed = 0
local typedText = ""
local startTime = 0
local redTime = 2
local wordTime = 3
local typeTime = 10
local shakeLetters = {}
local mistakes = 0
local mistakeFlashEnd = 0
local resultEnd = 0
local resultColor = Color(170, 0, 0)
local lastKeys = {}
local noAmmo = false
local phraseFont = "HG_LobotomyPhrase"
local phraseFontSize = 0

local function EnsurePhraseFont(text)
	if not text or text == "" then return end

	surface.SetFont("HG_LobotomyPhrase")

	local baseSize = ScreenScale(28)
	local spacing = ScreenScale(3)
	local baseWidth = surface.GetTextSize(text)
	if baseWidth <= 0 then return end

	local targetWidth = ScrW() * 0.92
	local spacingTotal = spacing * math.max(#text - 1, 0)
	local size = math.floor(baseSize * math.max(targetWidth - spacingTotal, 1) / baseWidth)

	size = math.Clamp(size, 24, math.floor(ScrH() * 0.5))
	if size == phraseFontSize then return end

	phraseFontSize = size
	phraseFont = "HG_LobotomyPhrase_" .. size

	surface.CreateFont(phraseFont, {
		font = "Times New Roman",
		size = size,
		weight = 700,
		antialias = true
	})
end

local function PickShakeLetters(length)
	shakeLetters = {}

	for i = 1, length do
		shakeLetters[i] = ScreenScale(math.Rand(1.5, 3.5))
	end
end

local function Finish(success)
	if not active then return end

	active = false
	mistakeFlashEnd = 0
	resultColor = success and Color(235, 235, 235) or Color(170, 0, 0)
	resultEnd = CurTime() + 0.35

	net.Start("HG_LobotomyResult")
		net.WriteBool(success)
		net.WriteString(typedText)
	net.SendToServer()
end

net.Receive("HG_LobotomyStart", function()
	introWord = net.ReadString()
	phrase = net.ReadString()
	redTime = net.ReadFloat()
	wordTime = net.ReadFloat()
	typeTime = net.ReadFloat()
	local raiseTime = net.ReadFloat()
	noAmmo = net.ReadBool()

	phraseKey = string.gsub(string.upper(phrase), "%s", "")
	EnsurePhraseFont(phrase)

	active = true
	typed = 0
	typedText = ""
	mistakes = 0
	mistakeFlashEnd = 0
	startTime = CurTime() + raiseTime
	resultEnd = 0
	lastKeys = {}

	PickShakeLetters(#introWord)
end)

net.Receive("HG_LobotomyAbort", function()
	if not active then return end

	active = false
	noAmmo = false
	resultColor = Color(170, 0, 0)
	resultEnd = CurTime() + 0.35
end)

local function KeyToLetter(key)
	return string.sub(KEY_LETTERS, key - KEY_A + 1, key - KEY_A + 1)
end

local function TypeLetter(letter)
	local expected = string.sub(phraseKey, typed + 1, typed + 1)

	if letter == expected then
		typed = typed + 1
		typedText = typedText .. letter

		if typed >= #phraseKey then
			Finish(true)
		end
	else
		mistakes = mistakes + 1
		mistakeFlashEnd = CurTime() + 0.15

		if mistakes > MAX_MISTAKES then
			Finish(false)
		end
	end
end

hook.Add("Think", "HG_LobotomyTyping", function()
	if not active or noAmmo then return end

	local now = CurTime()
	local typeStart = startTime + redTime + wordTime

	if now < typeStart then
		for key = KEY_A, KEY_Z do
			lastKeys[key] = input.IsKeyDown(key)
		end

		return
	end

	if gui.IsGameUIVisible() then return end

	for key = KEY_A, KEY_Z do
		local down = input.IsKeyDown(key)
		local wasDown = lastKeys[key]
		lastKeys[key] = down

		if down and not wasDown then
			TypeLetter(KeyToLetter(key))
			break
		end
	end
end)

hook.Add("Think", "HG_LobotomyTimeout", function()
	if not active or noAmmo then return end

	local typeStart = startTime + redTime + wordTime

	if (CurTime() - typeStart) >= typeTime then
		Finish(false)
	end
end)

hook.Add("CreateMove", "HG_LobotomyFreeze", function(cmd)
	if not active then return end

	cmd:ClearMovement()
	cmd:RemoveKey(IN_ATTACK)
	cmd:RemoveKey(IN_ATTACK2)
	cmd:RemoveKey(IN_JUMP)
	cmd:RemoveKey(IN_RELOAD)
end)

hook.Add("PlayerBindPress", "HG_LobotomyBlockBinds", function()
	if active then return true end
end)

hook.Add("HUDShouldDraw", "HG_LobotomyHideHUD", function()
	if active then return false end
end)

local function DrawRedIntro(now)
	local t = now - startTime
	if t < 0 or t >= redTime then return end

	local k = 1 - t / redTime

	surface.SetDrawColor(90, 0, 0, 60 * k)
	surface.DrawRect(0, 0, ScrW(), ScrH())

	for _ = 1, 10 do
		local w = math.Rand(30, 260) * ScreenScale(1)
		local h = math.Rand(2, 10) * ScreenScale(1)
		local x = math.Rand(-w, ScrW())
		local y = math.Rand(0, ScrH())

		surface.SetDrawColor(math.random(110, 190), 0, 0, math.random(20, 70) * k)
		surface.DrawRect(x, y, w, h)
	end
end

local function DrawIntroBlack(now)
	local wordStart = startTime + redTime
	local wordEnd = wordStart + wordTime

	if now < wordStart or now >= wordEnd then return end

	local fade = math.Clamp(math.min(now - wordStart, wordEnd - now) / 0.2, 0, 1)

	surface.SetDrawColor(0, 0, 0, 255 * fade)
	surface.DrawRect(0, 0, ScrW(), ScrH())
end

local function DrawIntroWord(now)
	local wordStart = startTime + redTime
	local wordEnd = wordStart + wordTime

	if now < wordStart or now >= wordEnd then return end

	local fade = math.Clamp(math.min(now - wordStart, wordEnd - now) / 0.25, 0, 1)

	surface.SetFont("HG_LobotomyIntro")

	local widths = {}
	local total = 0
	local tracking = ScreenScale(2)

	for i = 1, #introWord do
		local width = surface.GetTextSize(string.sub(introWord, i, i))
		widths[i] = width
		total = total + width

		if i < #introWord then
			total = total + tracking
		end
	end

	local x = (ScrW() - total) / 2
	local y = ScrH() * 0.45
	local tick = now * 9

	for i = 1, #introWord do
		local char = string.sub(introWord, i, i)
		local offsetX, offsetY = 0, 0

		if shakeLetters[i] then
			offsetX = math.sin(tick + i * 1.7) * shakeLetters[i]
			offsetY = math.cos(tick * 0.75 + i * 2.1) * shakeLetters[i]
		end

		draw.SimpleText(char, "HG_LobotomyIntro", x + offsetX + 1, y + offsetY + 1, Color(0, 0, 0, 180 * fade))
		draw.SimpleText(char, "HG_LobotomyIntro", x + offsetX + 2, y + offsetY, Color(235, 235, 235, 60 * fade))
		draw.SimpleText(char, "HG_LobotomyIntro", x + offsetX, y + offsetY, Color(235, 235, 235, 245 * fade))

		x = x + widths[i] + tracking
	end
end

local function DrawPhrase()
	surface.SetFont(phraseFont)

	local _, textHeight = surface.GetTextSize(phrase)
	local widths = {}
	local total = 0
	local spacing = ScreenScale(3)

	for i = 1, #phrase do
		local width = surface.GetTextSize(string.sub(phrase, i, i))
		widths[i] = width
		total = total + width

		if i < #phrase then
			total = total + spacing
		end
	end

	local x = (ScrW() - total) / 2
	local y = (ScrH() - textHeight) * 0.5
	local letterIndex = 0

	for i = 1, #phrase do
		local char = string.sub(phrase, i, i)

		if char ~= " " then
			letterIndex = letterIndex + 1

			local color = Color(120, 120, 120, 220)

			if letterIndex <= typed then
				color = Color(235, 235, 235, 245)
			end

			draw.SimpleText(char, phraseFont, x + 1, y + 1, Color(0, 0, 0, 180))
			draw.SimpleText(char, phraseFont, x, y, color)
		end

		x = x + widths[i] + spacing
	end
end

local function DrawNoAmmo(now)
	if now < startTime then return end

	local fade = math.Clamp((now - startTime) / 0.2, 0, 1)
	local text = "MAGAZINE IS FUCKING EMPTY"
	local lineHeight = ScrH() * 0.105
	local startY = ScrH() * 0.015

	surface.SetFont("HG_LobotomyEmpty")
	surface.SetDrawColor(0, 0, 0, 45 * fade)
	surface.DrawRect(0, 0, ScrW(), ScrH())

	for i = 1, 9 do
		local alpha = (205 + math.sin(now * 2.4 + i * 0.9) * 30) * fade
		local shade = (i % 2 == 0) and 225 or 190
		local x = ScrW() * 0.5 + math.sin(now * 1.7 + i * 1.3) * 2
		local y = startY + (i - 1) * lineHeight

		draw.SimpleText(text, "HG_LobotomyEmpty", x + 2, y + 2, Color(0, 0, 0, alpha * 0.75), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		draw.SimpleText(text, "HG_LobotomyEmpty", x, y, Color(shade, shade, shade, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

local function DrawResult(now)
	if resultEnd <= now then return end

	local k = (resultEnd - now) / 0.35

	surface.SetDrawColor(resultColor.r, resultColor.g, resultColor.b, 150 * k)
	surface.DrawRect(0, 0, ScrW(), ScrH())
end

hook.Add("DrawOverlay", "HG_LobotomyOverlay", function()
	local now = CurTime()

	if active then
		if noAmmo then
			DrawNoAmmo(now)
			return
		end

		DrawRedIntro(now)
		DrawIntroBlack(now)
		DrawIntroWord(now)

		local typeStart = startTime + redTime + wordTime

		if now >= typeStart then
			DrawPhrase()
		end

		if mistakeFlashEnd > now then
			local k = (mistakeFlashEnd - now) / 0.15

			surface.SetDrawColor(180, 0, 0, 90 * k)
			surface.DrawRect(0, 0, ScrW(), ScrH())
		end

		return
	end

	DrawResult(now)
end)
