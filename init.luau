--!strict
--[[
    AudioModule (init.luau)
    Zero-dependency, standalone Audio Engine for Roblox games.
    Supports SoundGroup channel routing, 2D/3D positional playback, randomized pitch,
    combo pitch scaling, tracked loops, and smooth BGM cross-fading.
--]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local script = script

local Types = require(script.Types)
local Channels = require(script.Channels)
local NetworkBridge = require(script.NetworkBridge)

local Logger = require(ReplicatedStorage.Packages.LoggerModule)

local log = Logger.create("AudioModule")

export type PlayOptions = Types.PlayOptions
export type SoundCategory = Types.SoundCategory
export type NetworkProvider = NetworkBridge.NetworkProvider

local AudioModule = {}
AudioModule.NetworkBridge = NetworkBridge

--- Sets a custom network provider (ByteNet, RemoteEvent, or custom) for AudioModule
function AudioModule.setNetworkProvider(provider: NetworkProvider)
	NetworkBridge.setProvider(provider)
end
local activeLoops: { [string]: Sound } = {}

-- Pitch combo state
local comboCount = 0
local lastPickupTime = 0
local COMBO_WINDOW_SECONDS = 3.0

-- BGM state
local currentBgmSound: Sound? = nil

local ContentProvider = game:GetService("ContentProvider")

-- Helper: Ensures physical Audio folder and sound templates exist in ReplicatedStorage
local function ensurePhysicalAudioFolder(): Folder
	local audioFolder = ReplicatedStorage:FindFirstChild("Audio") :: Folder?
	if not audioFolder then
		audioFolder = Instance.new("Folder")
		audioFolder.Name = "Audio"
		audioFolder.Parent = ReplicatedStorage
	end

	if audioFolder and not audioFolder:FindFirstChild("Grabbed") then
		local grabbedSound = Instance.new("Sound")
		grabbedSound.Name = "Grabbed"
		grabbedSound.SoundId = "rbxassetid://136401198004658"
		grabbedSound.Volume = 1.0
		grabbedSound.Looped = true
		grabbedSound.Parent = audioFolder
	end

	if audioFolder and not audioFolder:FindFirstChild("Flung") then
		local flungSound = Instance.new("Sound")
		flungSound.Name = "Flung"
		flungSound.SoundId = "rbxassetid://136680544819732"
		flungSound.Volume = 1.0
		flungSound.Parent = audioFolder
	end

	return audioFolder :: Folder
end

-- Initialize physical audio template folder on module require
ensurePhysicalAudioFolder()

-- Helper: Resolves sound ID and base volume from physical folder, instance, or ID
local function resolveSound(soundInput: any): (string?, number, number)
	if typeof(soundInput) == "Instance" and soundInput:IsA("Sound") then
		return soundInput.SoundId, soundInput.Volume, soundInput.PlaybackSpeed
	elseif typeof(soundInput) == "string" then
		-- Check physical ReplicatedStorage.Audio folder
		local audioFolder = ensurePhysicalAudioFolder()
		local soundTemplate = audioFolder:FindFirstChild(soundInput, true)
		if soundTemplate and soundTemplate:IsA("Sound") then
			return soundTemplate.SoundId, soundTemplate.Volume, soundTemplate.PlaybackSpeed
		end

		-- Raw asset ID
		if string.match(soundInput, "^rbxassetid://") or string.match(soundInput, "^http") then
			return soundInput, 1.0, 1.0
		elseif string.match(soundInput, "^%d+$") then
			return "rbxassetid://" .. soundInput, 1.0, 1.0
		end
	end

	return nil, 1.0, 1.0
end

--- Preloads sound instances, asset IDs, or folder keys asynchronously using ContentProvider.
-- @param soundInputs { any } - Array of Sound instances, Asset ID strings, or sound names
function AudioModule.preloadSounds(soundInputs: { any })
	local instancesToPreload: { Instance } = {}
	for _, soundInput in ipairs(soundInputs) do
		local soundId = resolveSound(soundInput)
		if soundId then
			local sound = Instance.new("Sound")
			sound.SoundId = soundId
			table.insert(instancesToPreload, sound)
		end
	end

	if #instancesToPreload > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(instancesToPreload)
				log("Preloaded sound instances via ContentProvider successfully")
			end)
		end)
	end
end

local function attachSoundApiLogging(sound: Sound, soundId: string)
	if sound.IsLoaded then
		log(string.format("🔊 [Sound API] Sound is loaded & playing (%s | Length: %.2fs)", soundId, sound.TimeLength))
	else
		log(string.format("⏳ [Sound API] Waiting for sound asset to load from CDN (%s)...", soundId))
		local conn: RBXScriptConnection?
		conn = sound.Loaded:Connect(function()
			if conn then
				conn:Disconnect()
				conn = nil
			end
			log(string.format("✅ [Sound API] Sound asset loaded successfully! (%s | Length: %.2fs)", soundId, sound.TimeLength))
		end)
	end

	sound.Ended:Connect(function()
		log(string.format("🔚 [Sound API] Sound playback ended naturally (%s)", soundId))
	end)

	sound.Stopped:Connect(function()
		log(string.format("⏹️ [Sound API] Sound playback stopped (%s)", soundId))
	end)
end

--- Plays a 2D or 3D one-shot sound effect.
-- @param soundInput any - Sound instance, folder name key, or Asset ID
-- @param options PlayOptions?
-- @return Sound?
function AudioModule.playOneShot(soundInput: any, options: PlayOptions?): Sound?
	local soundId, defaultVol, defaultPitch = resolveSound(soundInput)
	if not soundId then
		log("⚠️ playOneShot failed: could not resolve sound input:", tostring(soundInput))
		return nil
	end

	local opt = options or {}
	local volume = opt.volume or defaultVol
	local pitch = opt.pitch or defaultPitch

	-- Apply random pitch variance if requested (prevents sound repetition fatigue)
	if opt.pitchVariance and opt.pitchVariance > 0 then
		local rng = (math.random() * 2 - 1) * opt.pitchVariance
		pitch = math.clamp(pitch + rng, 0.1, 3.0)
	end

	local sound = Instance.new("Sound")
	sound.Name = "AudioModule_OneShot"
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.SoundGroup = Channels.GetGroup(opt.category or "SFX")
	sound.Parent = opt.parent or SoundService

	attachSoundApiLogging(sound, soundId)
	sound:Play()
	log(string.format("🎵 playOneShot: %s | Vol: %.2f | Pitch: %.2f | Parent: %s", soundId, volume, pitch, sound.Parent and sound.Parent.Name or "Nil"))

	local autoCleanupTime = sound.TimeLength > 0 and (sound.TimeLength + 0.5) or 10
	Debris:AddItem(sound, autoCleanupTime)

	return sound
end

--- Plays a coin/item pickup sound with dynamic combo pitch escalation (1.0 -> 1.5).
-- @param soundInput any
-- @param parent Instance?
-- @return Sound?
function AudioModule.playPickupCombo(soundInput: any, parent: Instance?): Sound?
	local now = os.clock()
	if (now - lastPickupTime) > COMBO_WINDOW_SECONDS then
		comboCount = 0
	end

	comboCount += 1
	lastPickupTime = now

	local calculatedPitch = math.min(1.5, 1.0 + ((comboCount - 1) * 0.05))
	return AudioModule.playOneShot(soundInput, {
		parent = parent,
		pitch = calculatedPitch,
		category = "SFX",
	})
end

--- Plays a tracked looped sound effect.
-- @param loopId string - Unique identifier for the loop
-- @param soundInput any
-- @param options PlayOptions?
-- @return Sound?
function AudioModule.playLooped(loopId: string, soundInput: any, options: PlayOptions?): Sound?
	if activeLoops[loopId] then return activeLoops[loopId] end

	local soundId, defaultVol, defaultPitch = resolveSound(soundInput)
	if not soundId then
		log("⚠️ playLooped failed: could not resolve sound input:", tostring(soundInput))
		return nil
	end

	local opt = options or {}
	local sound = Instance.new("Sound")
	sound.Name = "AudioModule_Loop_" .. loopId
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = opt.volume or defaultVol
	sound.PlaybackSpeed = opt.pitch or defaultPitch
	sound.SoundGroup = Channels.GetGroup(opt.category or "SFX")
	sound.Parent = opt.parent or SoundService

	attachSoundApiLogging(sound, soundId)
	sound:Play()
	activeLoops[loopId] = sound
	log(string.format("🔄 playLooped (%s): %s | Vol: %.2f | Parent: %s", loopId, soundId, sound.Volume, sound.Parent and sound.Parent.Name or "Nil"))

	return sound
end

--- Stops a tracked looped sound with optional fade-out.
-- @param loopId string
-- @param fadeOutTime number?
function AudioModule.stopLooped(loopId: string, fadeOutTime: number?)
	local sound = activeLoops[loopId]
	if not sound then return end

	activeLoops[loopId] = nil
	log(string.format("🛑 stopLooped (%s)", loopId))

	if fadeOutTime and fadeOutTime > 0 then
		local fade = TweenService:Create(sound, TweenInfo.new(fadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
		fade:Play()
		fade.Completed:Connect(function()
			sound:Stop()
			sound:Destroy()
		end)
	else
		sound:Stop()
		sound:Destroy()
	end
end

--- Plays or cross-fades background music (BGM).
-- @param soundInput any
-- @param fadeDuration number?
function AudioModule.playBGM(soundInput: any, fadeDuration: number?)
	local duration = fadeDuration or 1.5
	local soundId, defaultVol = resolveSound(soundInput)
	if not soundId then return end

	local newBgm = Instance.new("Sound")
	newBgm.Name = "AudioModule_BGM"
	newBgm.SoundId = soundId
	newBgm.Looped = true
	newBgm.Volume = 0
	newBgm.SoundGroup = Channels.GetGroup("Music")
	newBgm.Parent = SoundService
	newBgm:Play()

	-- Fade in new track
	TweenService:Create(newBgm, TweenInfo.new(duration), { Volume = defaultVol }):Play()

	-- Fade out current track
	if currentBgmSound then
		local oldBgm = currentBgmSound
		local fadeOut = TweenService:Create(oldBgm, TweenInfo.new(duration), { Volume = 0 })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			oldBgm:Stop()
			oldBgm:Destroy()
		end)
	end

	currentBgmSound = newBgm
end

--- Configures volume for a specific SoundGroup channel (Master, SFX, Music, UI, Voice).
function AudioModule.setVolume(category: SoundCategory | "Master", volume: number)
	Channels.SetVolume(category, volume)
end

return AudioModule
