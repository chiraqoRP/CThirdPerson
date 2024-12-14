local CoreClass = {}
CoreClass.__index = CoreClass

local shoulderToggle = {}

function CoreClass:GetShoulderToggle(ply)
	return shoulderToggle[ply] or false
end

function CoreClass:SetShoulderToggle(ply, toggle)
	shoulderToggle[ply] = toggle
end

local PLAYER = FindMetaTable("Player")
local pGetViewEntity = PLAYER.GetViewEntity
local allowed = CreateConVar("sv_thirdperson_allowed", 1, cf)
local clEnabled = nil

if CLIENT then
	clEnabled = CreateClientConVar("cl_thirdperson_enable", 1, true, true, "", 0, 1)
end

local pGetInfoNum = PLAYER.GetInfoNum
local cachedCanDoThirdPerson = {}

function CoreClass:CanDoThirdPerson(ply, forceCheck)
	if !forceCheck then
		return cachedCanDoThirdPerson[ply] or false
	end

	local isEnabled = CLIENT and clEnabled:GetBool() or pGetInfoNum(ply, "cl_thirdperson_enable", 0) == 1

	if !allowed:GetBool() or !isEnabled then
		return false
	end

	local viewEntity = pGetViewEntity(ply)
	local isSpectating = IsValid(viewEntity) and viewEntity != ply

	if isSpectating or !ply:CanOverrideView() then
		return false
	end

	return true
end

local ENTITY = FindMetaTable("Entity")
local eIsFlagSet = ENTITY.IsFlagSet
local pGetHull = PLAYER.GetHull
local eGetBonePosition = ENTITY.GetBonePosition
local eGetPos = ENTITY.GetPos
local pGetViewOffset = PLAYER.GetViewOffset
local pGetViewOffsetDucked = PLAYER.GetViewOffsetDucked
local eGetMoveType = ENTITY.GetMoveType
local traceMin, traceMax = Vector(-10, -10, -10), Vector(10, 10, 10)
local lastFinalOrigin = Vector(0, 0, 0)
local lastViewOrigin = Vector(0, 0, 0)
local lastViewAngles = Angle(0, 0, 0)

function CoreClass:GetViewOrigin(ply, curAng, horizontalAng, verticalAng, distanceMul, doTrace)
	local viewOrigin = Vector(0, 0, 0)

	if !eIsFlagSet(ply, FL_ONGROUND) and eIsFlagSet(ply, FL_ANIMDUCKING) then
		local _, pMaxs = pGetHull(ply)
		local bonePos = eGetBonePosition(ply, 0)
		bonePos.z = bonePos.z - (pMaxs.z / 2)

		viewOrigin:Set(bonePos)
	else
		viewOrigin:Set(eGetPos(ply))
	end

	viewOrigin:Add(pGetViewOffset(ply))

	local crouchViewOffset = pGetViewOffsetDucked(ply)
	crouchViewOffset:Mul(0.5 * self:GetCrouchFactor(ply))

	viewOrigin:Add(verticalAng)
	viewOrigin:Add(horizontalAng)

	local isNoClipping = eGetMoveType(ply) == MOVETYPE_NOCLIP

	if !isNoClipping then
		viewOrigin:Sub(crouchViewOffset)
	end

	-- COMMENT
	if viewOrigin == lastViewOrigin and curAng == lastViewAngles then
		return lastFinalOrigin
	end

	lastViewOrigin = viewOrigin
	lastViewAngles = curAng

	if !doTrace then
		return viewOrigin
	end

	local traceData = {}
	traceData.start = viewOrigin
	traceData.endpos = traceData.start - curAng:Forward() * distanceMul
	traceData.filter = ply
	traceData.ignoreworld = isNoClipping
	traceData.mins = traceMin
	traceData.maxs = traceMax

	local finalOrigin = util.TraceHull(traceData).HitPos

	-- COMMENT
	lastFinalOrigin = finalOrigin

	return finalOrigin
end

local pGetActiveWeapon = PLAYER.GetActiveWeapon
local eGetVelocity = ENTITY.GetVelocity
local pGetWalkSpeed = PLAYER.GetWalkSpeed
local pGetCrouchedWalkSpeed = PLAYER.GetCrouchedWalkSpeed
local horizontalOffset = nil
local verticalOffset = nil
local distanceOffset = nil

if CLIENT then
	horizontalOffset = CreateClientConVar("cl_thirdperson_offset_horizontal", 0, true, true, "", -10, 10)
	verticalOffset = CreateClientConVar("cl_thirdperson_offset_vertical", 10, true, true, "", 0, 15)
	distanceOffset = CreateClientConVar("cl_thirdperson_offset_distance", 50, true, true, "", 0, 100)
end

local crouchOffset = {5, -5, -5}
local crouchWalkOffset = {0, 7.5, 0}
local aimOriginOffset = {5, 0, -10}
local aimCrouchOffset = {5, 0, -5}
local lastHorizontalMul, lastVerticalMul = 1, 1

function CoreClass:CalculateOriginOffsets(ply, velocity, sightDelta)
	local horizontalMul = CLIENT and horizontalOffset:GetFloat() or ply:GetInfoNum("cl_thirdperson_offset_horizontal", 0)
	local verticalMul = CLIENT and verticalOffset:GetFloat() or ply:GetInfoNum("cl_thirdperson_offset_vertical", 10)
	local distanceMul = CLIENT and distanceOffset:GetFloat() or ply:GetInfoNum("cl_thirdperson_offset_distance", 50)
	local crouchFactor = self:GetCrouchFactor(ply)

	if crouchFactor != 0 then
		horizontalMul = Lerp(crouchFactor, horizontalMul, horizontalMul + crouchOffset[1])
		verticalMul = Lerp(crouchFactor, verticalMul, verticalMul + crouchOffset[2])
		distanceMul = Lerp(crouchFactor, distanceMul, distanceMul + crouchOffset[3])
	end

	sightDelta = sightDelta or self:GetWeaponSightDelta(pGetActiveWeapon(ply))

	local uncrouchedSightDelta = sightDelta * (1 - crouchFactor)

	if uncrouchedSightDelta != 0 then
		horizontalMul = Lerp(uncrouchedSightDelta, horizontalMul, horizontalMul + aimOriginOffset[1])
		distanceMul = Lerp(uncrouchedSightDelta, distanceMul, distanceMul + aimOriginOffset[3])
	end

	local crouchedSightDelta = sightDelta * crouchFactor

	if crouchedSightDelta != 0 then
		horizontalMul = Lerp(crouchedSightDelta, horizontalMul, horizontalMul + aimCrouchOffset[1])
		distanceMul = Lerp(crouchedSightDelta, distanceMul, distanceMul + aimCrouchOffset[3])
	end

	velocity = velocity or eGetVelocity(ply):Length()

	local walkSpeed = pGetWalkSpeed(ply)
	local crouchSpeedMult = pGetCrouchedWalkSpeed(ply)
	local walkFactor = math.ease.InOutSine(math.min(walkSpeed * crouchSpeedMult, velocity) / (walkSpeed * crouchSpeedMult))

	verticalMul = Lerp(walkFactor * crouchFactor, verticalMul, verticalMul + crouchWalkOffset[2])

	-- COMMENT
	lastHorizontalMul, lastVerticalMul = horizontalMul, verticalMul

	return horizontalMul, verticalMul, distanceMul
end

function CoreClass:CalculateShoulderAngle(ply, horizontalAng)
	local isLeftShoulder = shoulderToggle[ply]

	-- COMMENT
	local newAng = isLeftShoulder and -horizontalAng or horizontalAng
	local shoulderFactor = self:GetShoulderFactor(ply)

	-- COMMENT
	local shoulderMinuend = isLeftShoulder and shoulderFactor * 2 or 1
	local smoothedShoulder = math.ease.InOutSine(shoulderMinuend - shoulderFactor)
	local shoulderAng = Vector(0, 0, 0)

	shoulderAng.x = Lerp(smoothedShoulder, -newAng.x, newAng.x)
	shoulderAng.y = Lerp(smoothedShoulder, -newAng.y, newAng.y)
	shoulderAng.z = Lerp(smoothedShoulder, -newAng.z, newAng.z)

	return shoulderAng
end

local pGetRunSpeed = PLAYER.GetRunSpeed

function CoreClass:CalculateFOV(ply, fov, velocity, sightDelta)
	local baseFov, viewFov = fov, fov
	local isNoClipping = ply:GetMoveType() == MOVETYPE_NOCLIP

	if !isNoClipping then
		local walkSpeed, runSpeed = pGetWalkSpeed(ply), pGetRunSpeed(ply)
		velocity = velocity or eGetVelocity(ply):Length()

		viewFov = Lerp(math.ease.InOutSine(math.max(0, velocity - walkSpeed) / runSpeed), viewFov, baseFov * 1.1)
		viewFov = Lerp(self:GetCrouchFactor(ply), viewFov, baseFov * 0.9)
	end

	local wep = pGetActiveWeapon(ply)

	sightDelta = sightDelta or self:GetWeaponSightDelta(wep)

	if sightDelta != 0 then
		viewFov = Lerp(sightDelta, viewFov, baseFov * 0.8)
	end

	local sightZoom = self:GetWeaponSightZoom(wep, viewFov)

	if sightDelta != 0 and sightZoom then
		viewFov = Lerp(sightDelta, viewFov, viewFov / sightZoom)
	end

	return viewFov
end

local crouchFactors = {}

function CoreClass:GetCrouchFactor(ply, noEase)
	local cachedFactor = crouchFactors[ply]

	if noEase then
		return cachedFactor or 0
	end

	return math.ease.InOutSine(cachedFactor or 0)
end

function CoreClass:SetCrouchFactor(ply, crouchFactor)
	crouchFactors[ply] = crouchFactor
end

local shoulderFactors = {}

function CoreClass:GetShoulderFactor(ply, noEase)
	local cachedFactor = shoulderFactors[ply]

	if noEase then
		return cachedFactor or 0
	end

	return math.ease.InOutSine(cachedFactor or 0)
end

function CoreClass:SetShoulderFactor(ply, shoulderFactor)
	shoulderFactors[ply] = shoulderFactor
end

local pKeyDown = PLAYER.KeyDown
local pGetDuckSpeed = PLAYER.GetDuckSpeed
local tickRate = math.Round(1 / engine.TickInterval())
local crouchChangeRate = math.Round(3 * (tickRate / 66))
local shoulderChangeRate = math.Round(3 * (tickRate / 66))

function CoreClass:UpdateFactors(ply)
	if !IsValid(ply) then
		return
	end

	local canDoThirdPerson = self:CanDoThirdPerson(ply, true)

	cachedCanDoThirdPerson[ply] = canDoThirdPerson or nil

	if !canDoThirdPerson then
		return false
	end

	local tickInterval = engine.TickInterval()
	local isCrouching = (eIsFlagSet(ply, FL_ONGROUND) and pKeyDown(ply, IN_DUCK)) or eIsFlagSet(ply, FL_DUCKING)
	local crouchTo = isCrouching and 1 or 0
	local adjustedCrouchRate = crouchChangeRate * (math.Round(pGetDuckSpeed(ply), 1) / 0.1)
	local crouchFrac = math.Approach(self:GetCrouchFactor(ply, true), crouchTo, adjustedCrouchRate * tickInterval)

	self:SetCrouchFactor(ply, crouchFrac)

	local shoulderTo = shoulderToggle[ply] and 1 or 0
	local shoulderFrac = math.Approach(self:GetShoulderFactor(ply, true), shoulderTo, shoulderChangeRate * tickInterval)

	self:SetShoulderFactor(ply, shoulderFrac)

	return true
end

local eEyeAngles = ENTITY.EyeAngles

function CoreClass:CalcAimOffset(ply)
	if !IsValid(ply) then
		return vector_origin
	end

	local curAng = eEyeAngles(ply)

	-- COMMENT
	local horizontalAng, verticalAng = self:CalculateShoulderAngle(ply, curAng:Right()), curAng:Up()
	local horizontalMul, verticalMul = lastHorizontalMul, lastVerticalMul

	-- COMMENT
	if SERVER then
		horizontalMul, verticalMul, _ = self:CalculateOriginOffsets(ply)
	end

	-- HACK: 
	horizontalAng:Mul(horizontalMul / 2)
	verticalAng:Mul(verticalMul / 2)

	local aimOffset = Vector(0, 0, 0)
	aimOffset:Add(horizontalAng)
	aimOffset:Add(verticalAng)

	-- local isNoClipping = eGetMoveType(ply) == MOVETYPE_NOCLIP

	-- -- COMMENT
	-- if !isNoClipping and ply:OnGround() then
	-- 	-- COMMENT
	-- 	local crouchFrac = self:GetCrouchFactor(ply)
	-- 	local crouchViewOffset = ply:GetViewOffsetDucked()

	-- 	aimOffset.z = aimOffset.z + crouchViewOffset.z * math.min(0.80, crouchFrac)
	-- end

	return aimOffset
end

local sightDeltaFuncs = {
	["arccw_base"] = function(wep)
		return math.ease.InOutSine(1 - wep:GetSightDelta())
	end,
	["arc9_base"] = function(wep)
		return math.ease.InOutSine(wep:GetSightDelta())
	end,
	["mg_base"] = function(wep)
		return math.ease.InOutSine(wep:GetAimDelta())
	end,
	["cw_base"] = function(wep)
		if CLIENT then
			local to = wep.dt.State == CW_AIMING and 1 or 0
			local approachSpeed = wep.ApproachSpeed or 0

			-- Piggybacks off a var used in CW2's WEAPON:CalcView :P
			local sightDelta = Lerp(FrameTime() * approachSpeed, wep._SightDelta or 0, to)

			-- HACK: CW2 doesn't have a SightDelta var.
			wep._SightDelta = sightDelta

			return math.ease.InOutSine(sightDelta)
		end

		-- HACK: CW2 doesn't have a SightDelta var, instead using Lerp and FrameTime.
		-- Because of this, we cannot have any lerp on serverside.
		return wep.dt.State == CW_AIMING and 1 or 0
	end,
	["tfa_gun_base"] = function(wep)
		-- NOTE: Untested, no promises that this works!
		return math.ease.InOutSine(wep.IronSightsProgress)
	end,
	["bobs_gun_base"] = function(wep)
		return wep:GetIronSights() and 1 or 0
	end
}

local eIsValid = ENTITY.IsValid

function CoreClass:GetWeaponSightDelta(wep)
	local sightDelta = 0

	if !wep or !eIsValid(wep) then
		return sightDelta
	end

	local getFunc = sightDeltaFuncs[wep.Base]

	if !getFunc then
		return sightDelta
	end

	return getFunc(wep)
end

local arccwScopeCVar, arc9ScopeCVar = nil, nil
local sightZoomFuncs = {
	["arccw_base"] = function(wep, fov)
		if arccwScopeCVar:GetBool() then
			return
		end

		local sight = wep:GetActiveSights()
		local sightZoom = sight and sight.ScopeMagnification or 1.0

		return sightZoom
	end,
	["arc9_base"] = function(wep, fov)
		if arc9ScopeCVar:GetBool() then
			return
		end

		local sight = wep:GetSight()
		local sightZoom = sight.Magnification or 1

	    if !sight or sight.Disassociate then
			return
		end

        local atttbl = sight.atttbl

        if atttbl and atttbl.RTScope and !atttbl.RTCollimator then
            -- target = (self:GetOwner():GetFOV() / self:GetRTScopeFOV())

            local scrW, scrH = ScrW(), ScrH()
            local screenAmt = ((scrW - scrH) / scrW) * (atttbl.ScopeScreenRatio or 0.5) * 2

            sightZoom = math.max((fov / (wep:GetRTScopeFOV() or fov)) * screenAmt, 1)
        end

		return sightZoom
	end,
	["cw_base"] = function(wep, fov)
		if !wep.telescopicsFOVRange or !wep.telescopicsFOVIndex then
			return
		end

		return wep.telescopicsFOVRange[wep.telescopicsFOVIndex] * 0.5
	end
}

local fetchedConvars = false

function CoreClass:GetWeaponSightZoom(wep, fov)
	if !wep then
		return
	end

	if !fetchedConvars then
		arccwScopeCVar = GetConVar("arccw_cheapscopes")
		arc9ScopeCVar = GetConVar("ARC9_cheapscopes")
	end

	local getFunc = sightZoomFuncs[wep.Base]

	if !getFunc then
		return
	end

	return getFunc(wep, fov)
end

CThirdPerson = CoreClass