if not SERVER then return end

util.AddNetworkString("HG_LobotomyStart")
util.AddNetworkString("HG_LobotomyAbort")
util.AddNetworkString("HG_LobotomyResult")

local INTRO_WORDS = { "Lobotomy", "PENETRATE" }
local PHRASES = { "PSYCHOLOGICAL BARRIER", "HOLD STEADY" }
local RED_TIME = 2
local WORD_TIME = 3
local TYPE_TIME = 10
local RAISE_TIME = 1
local NO_AMMO_TIME = 3
local BRAIN_DAMAGE = 0.15
local FAINT_DELAY = 10
local FAINT_TIME = 30
local RETRY_COOLDOWN = 1

local function IsMelee(wep)
	if not IsValid(wep) then return false end
	if wep:GetClass() == "weapon_hands_sh" or wep:GetClass() == "weapon_hg_coolhands" then return false end
	return wep.ismelee2 or wep.ismelee or wep.Base == "weapon_melee"
end

local function IsGun(wep)
	return IsValid(wep) and ishgweapon(wep) and wep.CanSuicide and not IsMelee(wep)
end

local NECK_CUT_PATTERNS = {
	"knife",
	"katana",
	"machete",
	"sword",
	"axe",
	"hatchet",
	"tomahawk",
	"bottlebroken",
	"glassshard"
}

local function IsNeckCutWeapon(wep)
	if not IsValid(wep) or not IsMelee(wep) then return false end

	local class = string.lower(wep:GetClass())
	local name = string.lower(wep.PrintName or "")
	if string.find(class, "spear", 1, true) then return false end

	for _, pattern in ipairs(NECK_CUT_PATTERNS) do
		if string.find(class, pattern, 1, true) or string.find(name, pattern, 1, true) then
			return true
		end
	end

	return false
end

local function ClearState(ply, keepRaised)
	if not IsValid(ply) then return end

	if ply.HG_LobotomyTimer then
		timer.Remove(ply.HG_LobotomyTimer)
	end

	ply.HG_LobotomyTimer = nil
	ply.HG_LobotomyActive = nil
	ply.HG_LobotomyWord = nil
	ply.HG_LobotomyWeapon = nil
	ply.HG_LobotomyDeadline = nil
	ply.HG_LobotomyIsMelee = nil
	ply.HG_LobotomyShooting = nil
	ply.HG_LobotomyNoAmmo = nil
	ply.HG_NeckCut = nil
	ply:SetNWBool("HG_NeckCut", false)

	if not keepRaised then
		ply.suiciding = false
		ply.startsuicide = nil
		ply:SetNWBool("suiciding", false)
	end

	ply:SetNWFloat("willsuicide", 0)
end

local function FailPrompt(ply)
	if not IsValid(ply) then return end

	local wasActive = ply.HG_LobotomyActive
	local wep = ply.HG_LobotomyWeapon

	ClearState(ply)

	if not wasActive then return end

	net.Start("HG_LobotomyAbort")
	net.Send(ply)

	if IsValid(wep) and ply:Alive() then
		if isfunction(hg.drop) then
			hg.drop(ply, wep)
		else
			ply:DropWeapon(wep)
		end
	end

	ply.HG_LobotomyCooldown = CurTime() + RETRY_COOLDOWN
	ply:ChatPrint("You couldn't bring yourself to do it.")
end

local function AbortNoAmmo(ply)
	if not IsValid(ply) then return end

	local wasActive = ply.HG_LobotomyActive

	ClearState(ply)

	if not wasActive then return end

	net.Start("HG_LobotomyAbort")
	net.Send(ply)

	ply.HG_LobotomyCooldown = CurTime() + RETRY_COOLDOWN
end

local function Faint(ply)
	if not IsValid(ply) or not ply:Alive() or not ply.organism then return end

	local org = ply.organism
	local wasOut = org.needotrub

	org.needotrub = true

	if wasOut then return end

	local token = (org.HG_LobotomyFaintToken or 0) + 1
	org.HG_LobotomyFaintToken = token

	timer.Simple(FAINT_TIME, function()
		if not IsValid(ply) or not ply:Alive() or not ply.organism then return end
		if ply.organism.HG_LobotomyFaintToken ~= token then return end

		ply.organism.needotrub = false
	end)
end

local function CutNeck(ply, wep)
	ply.HG_NeckCut = true
	ply:SetNWBool("HG_NeckCut", true)
	ply:SetNWFloat("willsuicide", 0)

	local holdTime = (IsValid(wep) and wep.SuicideTime) or 0.5

	timer.Simple(holdTime + 0.25, function()
		if not IsValid(ply) then return end

		ply.HG_NeckCut = nil
		ply:SetNWBool("HG_NeckCut", false)

		if ply.HG_LobotomyActive then return end

		ply.suiciding = false
		ply.startsuicide = nil
		ply:SetNWBool("suiciding", false)
		ply:SetNWFloat("willsuicide", 0)
	end)
end

local function SucceedPrompt(ply)
	if not IsValid(ply) or not ply:Alive() then return end

	local wep = ply.HG_LobotomyWeapon
	local isMelee = ply.HG_LobotomyIsMelee

	if not IsValid(wep) or ply:GetActiveWeapon() ~= wep then
		ClearState(ply)
		return
	end

	ClearState(ply, true)

	ply.suiciding = true
	ply.startsuicide = ply.startsuicide or (CurTime() - 1)
	ply:SetNWBool("suiciding", true)
	ply:SetNWFloat("willsuicide", 0)

	if IsNeckCutWeapon(wep) then
		CutNeck(ply, wep)
		return
	end

	if isMelee then
		local org = ply.organism
		if not org then
			ClearState(ply)
			return
		end

		org.brain = math.min((org.brain or 0) + BRAIN_DAMAGE, 1)

		ply:ViewPunch(Angle(-4, 0, 0))
		ply:EmitSound("Flesh.Break", 60, math.random(90, 110))

		ply.HG_LobotomyShooting = true

		timer.Simple(0.5, function()
			if not IsValid(ply) then return end

			ply.HG_LobotomyShooting = nil

			if not ply.HG_LobotomyActive then
				ply.suiciding = false
				ply.startsuicide = nil
				ply:SetNWBool("suiciding", false)
				ply:SetNWFloat("willsuicide", 0)
			end
		end)

		timer.Simple(FAINT_DELAY, function()
			Faint(ply)
		end)
	else
		ply.HG_LobotomyShooting = true
		ply:SetNWFloat("willsuicide", CurTime() + 0.15)

		timer.Simple(3, function()
			if not IsValid(ply) then return end

			ply.HG_LobotomyShooting = nil

			if not ply.HG_LobotomyActive then
				ply.suiciding = false
				ply.startsuicide = nil
				ply:SetNWBool("suiciding", false)
				ply:SetNWFloat("willsuicide", 0)
			end
		end)
	end
end

local function StartPrompt(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
	if ply.HG_LobotomyActive then return end
	if (ply.HG_LobotomyCooldown or 0) > CurTime() then return end
	if ply.suiciding or ply:GetNWFloat("willsuicide", 0) > 0 then return end
	if ply.organism and ply.organism.otrub then return end

	local wep = ply:GetActiveWeapon()
	local isMelee = IsMelee(wep)
	local isGun = IsGun(wep)

	if not isMelee and not isGun then
		ply:ChatPrint("You need a melee weapon or a gun.")
		return
	end

	if isGun and wep.reload then
		ply:ChatPrint("Finish reloading first.")
		return
	end

	local noAmmo = isGun and wep:Clip1() <= 0
	local introWord = INTRO_WORDS[math.random(#INTRO_WORDS)]
	local phrase = PHRASES[math.random(#PHRASES)]
	local key = string.gsub(string.upper(phrase), "%s", "")
	local token = (ply.HG_LobotomyToken or 0) + 1
	local duration = RAISE_TIME + (noAmmo and NO_AMMO_TIME or (RED_TIME + WORD_TIME + TYPE_TIME))

	ply.HG_LobotomyActive = true
	ply.HG_LobotomyWord = key
	ply.HG_LobotomyWeapon = wep
	ply.HG_LobotomyIsMelee = isMelee
	ply.HG_LobotomyNoAmmo = noAmmo
	ply.HG_LobotomyDeadline = CurTime() + duration + 0.3
	ply.HG_LobotomyToken = token
	ply.suiciding = true
	ply.startsuicide = CurTime()
	ply:SetNWBool("suiciding", true)
	ply:SetNWFloat("willsuicide", 0)

	net.Start("HG_LobotomyStart")
		net.WriteString(introWord)
		net.WriteString(phrase)
		net.WriteFloat(RED_TIME)
		net.WriteFloat(WORD_TIME)
		net.WriteFloat(TYPE_TIME)
		net.WriteFloat(RAISE_TIME)
		net.WriteBool(noAmmo)
	net.Send(ply)

	ply.HG_LobotomyTimer = "HG_LobotomyTimeout_" .. ply:EntIndex() .. "_" .. token

	timer.Create(ply.HG_LobotomyTimer, duration + 0.3, 1, function()
		if not IsValid(ply) or ply.HG_LobotomyToken ~= token then return end

		if noAmmo then
			AbortNoAmmo(ply)
		else
			FailPrompt(ply)
		end
	end)

	if noAmmo then
		timer.Simple(RAISE_TIME, function()
			if not IsValid(ply) or not ply.HG_LobotomyActive or not ply.HG_LobotomyNoAmmo then return end
			if ply.HG_LobotomyToken ~= token then return end

			local activeWep = ply:GetActiveWeapon()
			if IsValid(activeWep) and activeWep == wep and activeWep.PrimaryShootEmpty then
				activeWep:PrimaryShootEmpty()
			end
		end)
	end
end

concommand.Add("suicide", StartPrompt)

net.Receive("HG_LobotomyResult", function(_, ply)
	if not IsValid(ply) or not ply.HG_LobotomyActive then return end

	local success = net.ReadBool()
	local typed = net.ReadString()

	if not success or string.upper(typed) ~= ply.HG_LobotomyWord then
		FailPrompt(ply)
		return
	end

	if (ply.HG_LobotomyDeadline or 0) < CurTime() then
		FailPrompt(ply)
		return
	end

	SucceedPrompt(ply)
end)

hook.Add("StartCommand", "HG_LobotomyFreeze", function(ply, cmd)
	if ply.HG_LobotomyActive then
		cmd:ClearMovement()
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
		cmd:RemoveKey(IN_JUMP)
		cmd:RemoveKey(IN_RELOAD)
	end

	if ply.HG_LobotomyShooting then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
		cmd:RemoveKey(IN_RELOAD)
	end
end)

hook.Add("PlayerSwitchWeapon", "HG_LobotomyNoSwitch", function(ply)
	if ply.HG_LobotomyActive then
		return true
	end
end)

hook.Add("PlayerDeath", "HG_LobotomyReset", function(ply)
	if ply.HG_LobotomyActive then
		net.Start("HG_LobotomyAbort")
		net.Send(ply)
	end

	ClearState(ply)
end)

hook.Add("PlayerSpawn", "HG_LobotomyResetSpawn", function(ply)
	if ply.HG_LobotomyActive then
		net.Start("HG_LobotomyAbort")
		net.Send(ply)
	end

	ClearState(ply)
	ply.HG_LobotomyCooldown = nil
end)

hook.Add("PlayerDisconnected", "HG_LobotomyResetDisconnect", function(ply)
	ClearState(ply)
end)
