if not CLIENT then return end

hg = hg or {}
hg.OtrubMusicActive = false

local TRACK = "sound/meleecity/unethical_superstructure.mp3"
local TARGET_VOLUME = 0.16
local music
local loading = false
local volume = 0
local wasOtrub = false
local allowTrack = false
local channels = {}
local nextCleanup = 0

local oldPlayFile = sound.PlayFile
local oldPlayURL = sound.PlayURL
local oldPlay = sound.Play
local oldSurfacePlaySound = surface.PlaySound

local function IsOtrub()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return false end
	local org = ply.organism
	return org and org.otrub
end

local function TrackChannel(station)
	if IsValid(station) then
		channels[#channels + 1] = station
	end
end

sound.PlayFile = function(path, flags, callback)
	if hg.OtrubMusicActive and not allowTrack then return end
	return oldPlayFile(path, flags, function(station, ...)
		TrackChannel(station)
		if callback then callback(station, ...) end
	end)
end

sound.PlayURL = function(url, flags, callback)
	if hg.OtrubMusicActive then return end
	return oldPlayURL(url, flags, function(station, ...)
		TrackChannel(station)
		if callback then callback(station, ...) end
	end)
end

sound.Play = function(...)
	if hg.OtrubMusicActive then return end
	return oldPlay(...)
end

surface.PlaySound = function(...)
	if hg.OtrubMusicActive then return end
	return oldSurfacePlaySound(...)
end

local function StopOtherChannels()
	for i = #channels, 1, -1 do
		local channel = channels[i]
		if not IsValid(channel) then
			table.remove(channels, i)
		elseif channel ~= music then
			channel:Stop()
			table.remove(channels, i)
		end
	end
end

local function PruneChannels()
	for i = #channels, 1, -1 do
		local channel = channels[i]
		if not IsValid(channel) then
			table.remove(channels, i)
		elseif channel ~= music and channel:GetState() == GMOD_CHANNEL_STOPPED then
			table.remove(channels, i)
		end
	end
end

local function StopMusic()
	if IsValid(music) then
		music:Stop()
	end

	music = nil
	loading = false
	volume = 0
end

local function StartMusic()
	if IsValid(music) or loading then return end

	loading = true
	allowTrack = true
	sound.PlayFile(TRACK, "noblock noplay", function(station)
		loading = false
		if not IsValid(station) then return end
		music = station
		music:EnableLooping(true)
		music:SetVolume(0)
		music:Play()
	end)
	allowTrack = false
end

hook.Add("EntityEmitSound", "HG_OtrubSilence", function()
	if hg.OtrubMusicActive then return false end
end)

hook.Add("PlayerFootstep", "HG_OtrubSilence", function()
	if hg.OtrubMusicActive then return true end
end)

hook.Add("PlayerStartVoice", "HG_OtrubSilence", function()
	if hg.OtrubMusicActive then return true end
end)

hook.Add("Think", "HG_OtrubMusic", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then
		hg.OtrubMusicActive = false
		wasOtrub = false
		StopMusic()
		return
	end

	if CurTime() >= nextCleanup then
		nextCleanup = CurTime() + 1
		PruneChannels()
	end

	local otrub = IsOtrub()

	if otrub and not wasOtrub then
		wasOtrub = true
		hg.OtrubMusicActive = true
		RunConsoleCommand("stopsound")
		RunConsoleCommand("soundfade", "0", "1")
		if IsValid(ZCityMainMenuMusic) then ZCityMainMenuMusic:Stop() end
		StopMusic()
		StopOtherChannels()
		StartMusic()
	elseif otrub then
		StopOtherChannels()

		if IsValid(music) then
			local target = IsValid(MainMenu) and 0 or TARGET_VOLUME
			volume = math.Approach(volume, target, FrameTime() * 0.15)
			music:SetVolume(volume)
		end
	elseif wasOtrub then
		wasOtrub = false
		hg.OtrubMusicActive = false

		if IsValid(music) then
			volume = math.Approach(volume, 0, FrameTime() * 0.25)
			music:SetVolume(volume)

			if volume <= 0.001 then
				music:Stop()
				music = nil
			end
		end
	elseif IsValid(music) then
		volume = math.Approach(volume, 0, FrameTime() * 0.25)
		music:SetVolume(volume)

		if volume <= 0.001 then
			music:Stop()
			music = nil
		end
	end
end)

hook.Add("ShutDown", "HG_OtrubMusicStop", function()
	hg.OtrubMusicActive = false
	StopMusic()
end)
