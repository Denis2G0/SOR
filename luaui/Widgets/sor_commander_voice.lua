function widget:GetInfo()
	return {
		name      = "SOR Commander Voice",
		desc      = "Plays SOR Vale (Resistance) / Prime Node (Synth) voice on commander select + move/build orders. Voice files live at sounds/voice/en/sor/ — registered automatically by gamedata/soundsVoice.lua with clean voice attributes (gain=1, pitchmod=0, gainmod=0).",
		author    = "SOR",
		date      = "2026",
		license   = "GPL v2+",
		layer     = 0,
		enabled   = true,
	}
end

------------------------------------------------------------
-- Config
------------------------------------------------------------

local SELECT_VOLUME      = 0.9
local ORDER_VOLUME       = 0.8
local SELECT_COOLDOWN_FRAMES = 12   -- ~0.4 s between rotations on rapid clicks
local ORDER_COOLDOWN_FRAMES  = 24   -- ~0.8 s between order acks
local SOUND_CHANNEL      = 'ui'     -- non-positional, full volume, no rolloff

local VALE_SELECT  = { "sounds/voice/en/sor/vale-sel.wav", "sounds/voice/en/sor/vale-sel-1.wav", "sounds/voice/en/sor/vale-sel-2.wav", "sounds/voice/en/sor/vale-sel-3.wav", "sounds/voice/en/sor/vale-sel-4.wav", "sounds/voice/en/sor/vale-sel-5.wav", }
local VALE_ORDER   = { "sounds/voice/en/sor/vale-ok-1.wav", "sounds/voice/en/sor/vale-ok-2.wav", "sounds/voice/en/sor/vale-ok-3.wav", }
local PRIME_SELECT = { "sounds/voice/en/sor/prime-sel.wav", "sounds/voice/en/sor/prime-sel-1.wav", "sounds/voice/en/sor/prime-sel-2.wav", "sounds/voice/en/sor/prime-sel-3.wav", "sounds/voice/en/sor/prime-sel-4.wav", "sounds/voice/en/sor/prime-sel-5.wav", }
local PRIME_ORDER  = { "sounds/voice/en/sor/prime-ok-1.wav", "sounds/voice/en/sor/prime-ok-2.wav", "sounds/voice/en/sor/prime-ok-3.wav", }

-- Resistance commanders (Cor side after the 2026-04-26 faction swap).
local RESISTANCE_COMMANDERS = { "corcom", "corcomlvl2", "corcomlvl3", "corcomlvl4", "corcomlvl5", "corcomlvl6", "corcomlvl7", "corcomlvl8", "corcomlvl9", "corcomlvl10", "cordecom", }
-- Synth commanders (Arm side after the swap).
local SYNTH_COMMANDERS      = { "armcom", "armcomlvl2", "armcomlvl3", "armcomlvl4", "armcomlvl5", "armcomlvl6", "armcomlvl7", "armcomlvl8", "armcomlvl9", "armcomlvl10", "armdecom", "armcomnew", }

------------------------------------------------------------
-- Build unitDefID lookup once (cache per BAR perf rules)
------------------------------------------------------------

local commanderVoices = {}  -- [unitDefID] = { select = {...}, order = {...} }

local function buildLookup()
	local function add(names, selectList, orderList)
		for i = 1, #names do
			local def = UnitDefNames[names[i]]
			if def then
				commanderVoices[def.id] = { select = selectList, order = orderList }
			end
		end
	end
	add(RESISTANCE_COMMANDERS, VALE_SELECT,  VALE_ORDER)
	add(SYNTH_COMMANDERS,      PRIME_SELECT, PRIME_ORDER)
end

------------------------------------------------------------
-- State
------------------------------------------------------------

local spGetGameFrame      = Spring.GetGameFrame
local spGetSelectedUnits  = Spring.GetSelectedUnits
local spGetUnitDefID      = Spring.GetUnitDefID
local spPlaySoundFile     = Spring.PlaySoundFile
local mathRandom          = math.random

local lastSelectFrame = 0
local lastOrderFrame  = 0
local selectIndex     = {}  -- [unitDefID] = next-index-1 to play (round-robin)
local orderIndex      = {}

local pendingMouseClick = false  -- LMB pressed this tick — check selection on next Update

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function playRotating(list, indexTable, unitDefID, volume)
	if not list or #list == 0 then return end
	local nextIdx = ((indexTable[unitDefID] or 0) % #list) + 1
	indexTable[unitDefID] = nextIdx
	spPlaySoundFile(list[nextIdx], volume, SOUND_CHANNEL)
end

local function findSelectedCommander()
	local sel = spGetSelectedUnits()
	for i = 1, #sel do
		local udid = spGetUnitDefID(sel[i])
		if udid and commanderVoices[udid] then
			return udid
		end
	end
	return nil
end

------------------------------------------------------------
-- Callins
------------------------------------------------------------

function widget:Initialize()
	buildLookup()
	local n = 0
	for _ in pairs(commanderVoices) do n = n + 1 end
	Spring.Echo("[SOR-VOICE] Initialize: mapped " .. n .. " commander unitDefIDs, VALE_SELECT has " .. #VALE_SELECT .. " lines")
end

-- LMB press: defer voice trigger by one Update so Spring has finalized the new selection.
function widget:MousePress(_, _, button)
	if button == 1 then
		pendingMouseClick = true
	end
	return false  -- don't consume the click
end

function widget:Update()
	if not pendingMouseClick then return end
	pendingMouseClick = false

	local frame = spGetGameFrame()
	if frame < lastSelectFrame + SELECT_COOLDOWN_FRAMES then return end

	local udid = findSelectedCommander()
	if not udid then return end

	local list = commanderVoices[udid].select
	local nextIdx = ((selectIndex[udid] or 0) % #list) + 1
	selectIndex[udid] = nextIdx
	Spring.Echo("[SOR-VOICE] PLAY " .. list[nextIdx])
	spPlaySoundFile(list[nextIdx], SELECT_VOLUME, SOUND_CHANNEL)
	lastSelectFrame = frame
end

-- Move / build / attack / patrol etc. orders issued to a commander.
function widget:UnitCommand(unitID, unitDefID, _, cmdID)
	local voices = commanderVoices[unitDefID]
	if not voices then return end

	local frame = spGetGameFrame()
	if frame < lastOrderFrame + ORDER_COOLDOWN_FRAMES then return end

	-- Filter out passive / repeat-spam commands; only react to player-issued action commands.
	if cmdID == CMD.WAIT or cmdID == CMD.STOP or cmdID == CMD.REPEAT or cmdID == CMD.SET_WANTED_MAX_SPEED then
		return
	end

	playRotating(voices.order, orderIndex, unitDefID, ORDER_VOLUME)
	lastOrderFrame = frame
end
