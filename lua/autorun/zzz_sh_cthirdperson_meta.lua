local ENTITY = FindMetaTable("Entity")
local PLAYER = FindMetaTable("Player")
local cf = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED)
local antiPeek = CreateConVar("sv_thirdperson_antipeek", 1, cf, "", 0, 1)
local hasCachedClass, cCore = false, nil

if CLIENT then
	local eEyePos = ENTITY.EyePos

	local function DoFirstPersonAim(ply, viewOrigin, sightDelta)
		if sightDelta != 0 then
			local eyePos = eEyePos(ply)
	
			viewOrigin.x = Lerp(sightDelta, viewOrigin.x, eyePos.x)
			viewOrigin.y = Lerp(sightDelta, viewOrigin.y, eyePos.y)
			viewOrigin.z = Lerp(sightDelta, viewOrigin.z, eyePos.z)
	
			local shouldOverrideAim = viewOrigin:DistToSqr(eyePos) < 10
	
			return shouldOverrideAim
		end
	
		return false
	end

	local pGetActiveWeapon = PLAYER.GetActiveWeapon
	local eGetVelocity = ENTITY.GetVelocity
	local eIsValid = ENTITY.IsValid
	local fpAiming = CreateClientConVar("cl_thirdperson_fpaiming", 0, true, true, "", 0, 1)

	hook.Add("CalcView", "CThirdPerson.Main", function(ply, origin, angles, fov, zNear, zFar)
		if !hasCachedClass then
			cCore = CThirdPerson
		end

		if !cCore:CanDoThirdPerson(ply) then
			return
		end

		local curAng = angles -- ply.camAng or angle_zero
		local wep = pGetActiveWeapon(ply)
		local sightDelta = cCore:GetWeaponSightDelta(wep)
		local velocity = eGetVelocity(ply):Length()

		-- COMMENT
		local horizontalAng, verticalAng = cCore:CalculateShoulderAngle(ply, curAng:Right()), curAng:Up()

		-- COMMENT
		local horizontalMul, verticalMul, distanceMul = cCore:CalculateOriginOffsets(ply, velocity, sightDelta)
		horizontalAng:Mul(horizontalMul)
		verticalAng:Mul(verticalMul)

		-- COMMENT
		local finalOrigin = cCore:GetViewOrigin(ply, curAng, horizontalAng, verticalAng, distanceMul, true)

		-- COMMENT
		if !finalOrigin then
			return
		end

		local aimTypeOverriden = false

		if sightDelta != 0 and fpAiming:GetBool() then
			-- COMMENT
			aimTypeOverriden = DoFirstPersonAim(ply, finalOrigin, sightDelta)
		end

		-- COMMENT
		if aimTypeOverriden then
			return
		end

		-- COMMENT
		local viewFov = cCore:CalculateFOV(ply, fov, velocity, sightDelta)

		-- HACK: VManip still plays animations because it handles its queue in NeedsDepthPass and hook order in gmod is a trainwreck.
		-- if VManip then
		-- 	VManip.QueuedAnim = nil
		-- end

		origin:Set(finalOrigin)

		fov = viewFov
	end)

	hook.Add("ShouldDrawLocalPlayer", "CThirdPerson.DrawPlayer", function(ply)
		local canDo = cCore:CanDoThirdPerson(ply)

		if canDo and (cCore:GetWeaponSightDelta(pGetActiveWeapon(ply)) == 0 or !fpAiming:GetBool()) then
			return true
		end
	end)

	local pUserID = PLAYER.UserID
	local hiddenPlayers = {}
	local hiddenPlayerFrac = {}

	local function HideWorldModel(self, flags)
		local owner = self:GetOwner()

		if owner == LocalPlayer() then
			self.RenderOverride = nil

			return
		end

		local userID = pUserID(owner)

		if !hiddenPlayers[userID] then
			self:DrawWorldModel(flags)
		end
	end

	local eIsLineOfSightClear = ENTITY.IsLineOfSightClear
	local eIsEffectActive = ENTITY.IsEffectActive
	local eDrawShadow = ENTITY.DrawShadow
	local lastDrawThink = 0
	local didHide = false
	local doAntiPeek = false

	hook.Add("PrePlayerDraw", "CThirdPerson.HidePlayers", function(ply, flags)
		local client = LocalPlayer()

		-- COMMENT
		if ply == client then
			doAntiPeek = antiPeek:GetBool()
		end

		local shouldHide = cCore:CanDoThirdPerson(client) and doAntiPeek

		-- COMMENT
		if ply == client then
			return
		end

		if !shouldHide then
			didHide = didHide or false

			return
		end

		didHide = true

		local curTime = CurTime()
		local userID = pUserID(ply)

		if (lastDrawThink + 0.25) <= curTime then
			local isVisible = eIsLineOfSightClear(client, ply)

			if !isVisible then
				ply.__PreviousShadowStatus = eIsEffectActive(ply, EF_NOSHADOW)
				eDrawShadow(ply, false)
			elseif !hiddenPlayers[userID] and isVisible then
				eDrawShadow(ply, ply.__PreviousShadowStatus)
			end

			hiddenPlayers[userID] = !isVisible or nil
			lastDrawThink = curTime
		end

		local isHidden = hiddenPlayers[userID]
		local blendFrac = math.Approach(hiddenPlayerFrac[userID] or 1, !isHidden and 1 or 0, FrameTime() / 0.3)

		hiddenPlayerFrac[userID] = blendFrac

		render.SetBlend(Lerp(math.ease.InOutSine(blendFrac), 0, 1))

		if isHidden and blendFrac > 0.98 then
			return true
		end
	end)

	-- NOTE: If we add this hook last, it'll be the last PostPlayerDraw hook to run.
	-- Thanks to this, it (should) affect parented CSEnt's which are typically drawn in PostPlayerDraw.
	timer.Simple(0, function()
		hook.Add("PostPlayerDraw", "CThirdPerson.HidePlayers", function(ply, flags)
			if !didHide then return end

			local client = LocalPlayer()

			if ply == client then
				return
			end

			local userID = pUserID(ply)

			if hiddenPlayerFrac[userID] then
				render.SetBlend(1.0)
			end
		end)
	end)

	gameevent.Listen("player_disconnect")

	hook.Add("player_disconnect", "CThirdPerson.ClearHiddenTable", function(data)
		if hiddenPlayerFrac[data.userid] then
			hiddenPlayerFrac[data.userid] = nil
		end
	end)

	local lastCanDo = false

	hook.Add("Tick", "CThirdPerson.UpdateFactors", function()
		if !hasCachedClass then
			cCore = CThirdPerson
		end

		local canDo = cCore:UpdateFactors(LocalPlayer())

		-- We have to do this in Tick instead of PrePlayerDraw because PrePlayerDraw only runs for players in our PVS.
		local shouldUpdate, newFunc = nil, nil

		if !lastCanDo and canDo then
			shouldUpdate, newFunc = true, HideWorldModel
		elseif lastCanDo and !canDo then
			shouldUpdate = true

			-- COMMENT
			render.SetBlend(1)
		end

		if shouldUpdate then
			for i, ply in player.Iterator() do
				local wep = pGetActiveWeapon(ply)

				if IsValid(wep) then
					wep.RenderOverride = newFunc
				end
			end
		end

		lastCanDo = canDo
	end)

	local clEnabled = nil

	concommand.Add("cl_thirdperson_toggle", function(ply, cmd, args, argStr)
		clEnabled = clEnabled or GetConVar("cl_thirdperson_enable")

		if !clEnabled then
			return
		end

		clEnabled:SetBool(!clEnabled:GetBool())
	end)
else
	hook.Add("PlayerPostThink", "CThirdPerson.UpdateFactors", function(ply)
		if !hasCachedClass then
			cCore = CThirdPerson
		end

		cCore:UpdateFactors(ply)
	end)
end

local pGetInfoNum = PLAYER.GetInfoNum
local shoulderBind = nil

if CLIENT then
	shoulderBind = CreateClientConVar("cl_thirdperson_switchshoulder", "", true, true, "keybind, this isn't a concommand")
end

hook.Add("PlayerButtonDown", "CThirdPerson.ShoulderSwitch", function(ply, button)
	local shoulderKey = CLIENT and shoulderBind:GetInt() or pGetInfoNum(ply, "cl_thirdperson_switchshoulder", 0)

	if !shoulderKey or button != shoulderKey then
		return
	end

	if CLIENT and !IsFirstTimePredicted() then
		return
	end

	local isLeftShoulder = cCore:GetShoulderToggle(ply)

	cCore:SetShoulderToggle(ply, !isLeftShoulder)
end)

local fpAiming = GetConVar("cl_thirdperson_fpaiming")

hook.Add("EntityFireBullets", "CThirdPerson.ApplyAimOffset", function(ent, data)
	if CLIENT and ent != LocalPlayer() then
		return
	end

	if !ent:IsPlayer() or !cCore:CanDoThirdPerson(ent) then
		return
	end

	local wep = ent:GetActiveWeapon()
	local fpAimingEnabled = CLIENT and fpAiming:GetBool() or pGetInfoNum(ent, "cl_thirdperson_fpaiming", 0) == 1

	if IsValid(wep) and fpAimingEnabled and cCore:GetWeaponSightDelta(wep) >= 0.90 then
		return
	end

	local offset = cCore:CalcAimOffset(ent)
	local newOffset = data.Src + offset

	data.Src = newOffset

	return true
end)

local pGetVehicle = PLAYER.GetVehicle
local pAlive = PLAYER.Alive

function PLAYER:CanOverrideView()
	if !IsValid(pGetVehicle(self)) and pAlive(self) then
		return true
	end
end