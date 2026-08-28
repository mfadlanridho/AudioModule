--!strict
--[[
    Channels.luau
    Manages hierarchical SoundGroup channels under SoundService (Master -> SFX, Music, UI, Voice).
--]]

local SoundService = game:GetService("SoundService")

local Channels = {}

local masterGroup: SoundGroup
local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local uiGroup: SoundGroup
local voiceGroup: SoundGroup

local isInitialized = false

function Channels.Init()
	if isInitialized then return end

	masterGroup = SoundService:FindFirstChild("Master") :: SoundGroup
	if not masterGroup then
		masterGroup = Instance.new("SoundGroup")
		masterGroup.Name = "Master"
		masterGroup.Volume = 1.0
		masterGroup.Parent = SoundService
	end

	sfxGroup = masterGroup:FindFirstChild("SFX") :: SoundGroup
	if not sfxGroup then
		sfxGroup = Instance.new("SoundGroup")
		sfxGroup.Name = "SFX"
		sfxGroup.Volume = 1.0
		sfxGroup.Parent = masterGroup
	end

	musicGroup = masterGroup:FindFirstChild("Music") :: SoundGroup
	if not musicGroup then
		musicGroup = Instance.new("SoundGroup")
		musicGroup.Name = "Music"
		musicGroup.Volume = 0.5
		musicGroup.Parent = masterGroup
	end

	uiGroup = masterGroup:FindFirstChild("UI") :: SoundGroup
	if not uiGroup then
		uiGroup = Instance.new("SoundGroup")
		uiGroup.Name = "UI"
		uiGroup.Volume = 1.0
		uiGroup.Parent = masterGroup
	end

	voiceGroup = masterGroup:FindFirstChild("Voice") :: SoundGroup
	if not voiceGroup then
		voiceGroup = Instance.new("SoundGroup")
		voiceGroup.Name = "Voice"
		voiceGroup.Volume = 1.0
		voiceGroup.Parent = masterGroup
	end

	isInitialized = true
end

function Channels.GetGroup(category: string?): SoundGroup
	if not isInitialized then Channels.Init() end

	if category == "Music" then return musicGroup
	elseif category == "UI" then return uiGroup
	elseif category == "Voice" then return voiceGroup
	else return sfxGroup end
end

function Channels.SetVolume(category: string, volume: number)
	local group = Channels.GetGroup(category)
	if group then
		group.Volume = math.clamp(volume, 0, 1)
	end
end

return Channels
