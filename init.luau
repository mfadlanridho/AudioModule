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
local RunService = game:GetService("RunService")
local script = script

local Types = require(script.Types)
local Channels = require(script.Channels)
local NetworkBridge = require(script.NetworkBridge)

local LoggerModule = (ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("LoggerModule"))
	or (ReplicatedStorage:FindFirstChild("Submodules") and ReplicatedStorage.Submodules:FindFirstChild("LoggerModule"))
local Logger = if LoggerModule then require(LoggerModule) :: any else nil

local baseLog = if Logger and Logger.create then Logger.create("AudioModule") else function(...) print("[AudioModule]", ...) end

-- Per-sound logging is off by default: it floods the console in games that play many sounds a second.
local debugEnabled = false
local function log(...)
	if debugEnabled then
		baseLog(...)
	end
end

export type PlayOptions = Types.PlayOptions
export type SoundCategory = Types.SoundCategory
export type NetworkProvider = NetworkBridge.NetworkProvider

local AudioModule = {}
AudioModule.NetworkBridge = NetworkBridge

--- Sets a custom network provider (ByteNet, RemoteEvent, or custom) for AudioModule
function AudioModule.setNetworkProvider(provider: NetworkProvider)
	NetworkBridge.setProvider(provider)
end

--- Turns per-sound debug logging on or off (off by default).
function AudioModule.setDebug(enabled: boolean)
	debugEnabled = enabled
end

local activeLoops: { [string]: Sound } = {}
local activeAttachments: { [string]: Attachment } = {}

-- Last start time per sound id, for the minInterval throttle
local lastPlayed: { [string]: number } = {}

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

	return audioFolder :: Folder
end

-- Initialize physical audio template folder on module require
ensurePhysicalAudioFolder()

local registeredSounds: { [string]: any } = {}

--- Registers a dictionary of named sound configurations or asset IDs.
-- @param sounds { [string]: string | Types.SoundConfig }
function AudioModule.registerSounds(sounds: { [string]: any })
	for name, config in pairs(sounds) do
		registeredSounds[name] = config
	end
	log("Registered named sounds into audio registry")
end

-- Helper: Resolves sound ID and base volume from physical SoundService, physical folder, registered sounds, instance, or ID
local function resolveSound(soundInput: any): (string?, number, number, SoundCategory?, Sound?)
	if typeof(soundInput) == "Instance" and soundInput:IsA("Sound") then
		return soundInput.SoundId, soundInput.Volume, soundInput.PlaybackSpeed, nil, soundInput
	end

	-- 1. Registered sounds table first: a plain lookup, no instance search
	local isAlias = false
	local entry = if soundInput ~= nil then registeredSounds[soundInput] else nil
	if entry then
		if typeof(entry) == "table" and entry.soundId then
			return entry.soundId, entry.volume or 1.0, entry.pitch or 1.0, entry.category, nil
		elseif typeof(entry) == "string" then
			soundInput = entry
			isAlias = true
		end
	end

	if typeof(soundInput) == "string" and not isAlias then
		-- 2. Check physical SoundService (native Roblox sound container)
		local SoundService = game:GetService("SoundService")
		local physicalSound = SoundService:FindFirstChild(soundInput, true)
		if physicalSound and physicalSound:IsA("Sound") then
			return physicalSound.SoundId, physicalSound.Volume, physicalSound.PlaybackSpeed, nil, physicalSound
		end

		-- 3. Check physical ReplicatedStorage.Audio folder
		local audioFolder = ensurePhysicalAudioFolder()
		local soundTemplate = audioFolder:FindFirstChild(soundInput, true)
		if soundTemplate and soundTemplate:IsA("Sound") then
			return soundTemplate.SoundId, soundTemplate.Volume, soundTemplate.PlaybackSpeed, nil, soundTemplate
		end
	end

	if typeof(soundInput) == "string" then
		-- Raw asset ID
		if string.match(soundInput, "^rbxassetid://") or string.match(soundInput, "^http") then
			return soundInput, 1.0, 1.0, nil, nil
		elseif string.match(soundInput, "^%d+$") then
			return "rbxassetid://" .. soundInput, 1.0, 1.0, nil, nil
		end
	end

	return nil, 1.0, 1.0, nil, nil
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
	if not debugEnabled then return end

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
	if RunService:IsServer() then
		log("ℹ️ playOneShot called on Server. Routing to playOnAllClients for client-authoritative playback.")
		AudioModule.playOnAllClients(soundInput, options)
		return nil
	end

	local soundId, defaultVol, defaultPitch, registeredCategory, templateSound = resolveSound(soundInput)
	if not soundId then
		warn("[AudioModule] playOneShot failed: could not resolve sound input:", tostring(soundInput))
		return nil
	end

	local opt = options or {}

	-- Throttle: skip the sound if the same one started less than minInterval seconds ago
	if opt.minInterval and opt.minInterval > 0 then
		local now = os.clock()
		local last = lastPlayed[soundId]
		if last and now - last < opt.minInterval then
			return nil
		end
		lastPlayed[soundId] = now
	end

	local volume = opt.volume or defaultVol
	local pitch = opt.pitch or defaultPitch
	local category = opt.category or registeredCategory or "SFX"

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
	-- A template keeps the SoundGroup it was given in Studio unless a category is asked for
	if not opt.category and not registeredCategory and templateSound and templateSound.SoundGroup then
		sound.SoundGroup = templateSound.SoundGroup
	else
		sound.SoundGroup = Channels.GetGroup(category)
	end

	if opt.rollOffMinDistance then
		sound.RollOffMinDistance = opt.rollOffMinDistance
	elseif templateSound then
		sound.RollOffMinDistance = templateSound.RollOffMinDistance
	end

	if opt.rollOffMaxDistance then
		sound.RollOffMaxDistance = opt.rollOffMaxDistance
	elseif templateSound then
		sound.RollOffMaxDistance = templateSound.RollOffMaxDistance
	end

	if opt.rollOffMode then
		sound.RollOffMode = opt.rollOffMode
	elseif templateSound then
		sound.RollOffMode = templateSound.RollOffMode
	end

	local tempAttachment: Attachment? = nil
	if opt.parent then
		sound.Parent = opt.parent
	elseif opt.position then
		tempAttachment = Instance.new("Attachment")
		tempAttachment.Name = "AudioModule_TempAttachment"
		tempAttachment.WorldPosition = opt.position
		tempAttachment.Parent = workspace.Terrain
		sound.Parent = tempAttachment
	else
		sound.Parent = SoundService
	end

	attachSoundApiLogging(sound, soundId)
	sound:Play()
	log(string.format("🎵 playOneShot: %s | Vol: %.2f | Pitch: %.2f | Parent: %s", soundId, volume, pitch, sound.Parent and sound.Parent.Name or "Nil"))

	local cleanedUp = false
	local function cleanup()
		if cleanedUp then return end
		cleanedUp = true
		if tempAttachment then
			tempAttachment:Destroy()
			tempAttachment = nil
		end
		sound:Destroy()
	end

	sound.Ended:Once(cleanup)
	sound.Stopped:Once(cleanup)
	task.delay(15, cleanup)

	return sound
end

--- Plays a item pickup sound with dynamic combo pitch escalation (1.0 -> 1.5).
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
	local existing = activeLoops[loopId]
	if existing then
		if existing.Parent then return existing end

		-- The loop was destroyed with its parent; forget it so the id can be used again
		activeLoops[loopId] = nil
		local staleAttachment = activeAttachments[loopId]
		activeAttachments[loopId] = nil
		if staleAttachment then
			staleAttachment:Destroy()
		end
	end

	local soundId, defaultVol, defaultPitch, registeredCategory = resolveSound(soundInput)
	if not soundId then
		warn("[AudioModule] playLooped failed: could not resolve sound input:", tostring(soundInput))
		return nil
	end

	local opt = options or {}
	local category = opt.category or registeredCategory or "SFX"
	local sound = Instance.new("Sound")
	sound.Name = "AudioModule_Loop_" .. loopId
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = opt.volume or defaultVol
	sound.PlaybackSpeed = opt.pitch or defaultPitch
	sound.SoundGroup = Channels.GetGroup(category)

	if opt.rollOffMinDistance then sound.RollOffMinDistance = opt.rollOffMinDistance end
	if opt.rollOffMaxDistance then sound.RollOffMaxDistance = opt.rollOffMaxDistance end
	if opt.rollOffMode then sound.RollOffMode = opt.rollOffMode end

	if opt.parent then
		sound.Parent = opt.parent
	elseif opt.position then
		local tempAttachment = Instance.new("Attachment")
		tempAttachment.Name = "AudioModule_LoopAttachment_" .. loopId
		tempAttachment.WorldPosition = opt.position
		tempAttachment.Parent = workspace.Terrain
		sound.Parent = tempAttachment
		activeAttachments[loopId] = tempAttachment
	else
		sound.Parent = SoundService
	end

	attachSoundApiLogging(sound, soundId)
	if opt.fadeInTime and opt.fadeInTime > 0 then
		local targetVolume = sound.Volume
		sound.Volume = 0
		TweenService:Create(sound, TweenInfo.new(opt.fadeInTime), { Volume = targetVolume }):Play()
	end
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
	local attachment = activeAttachments[loopId]
	activeAttachments[loopId] = nil

	log(string.format("🛑 stopLooped (%s)", loopId))

	local function finalize()
		sound:Stop()
		sound:Destroy()
		if attachment then
			attachment:Destroy()
		end
	end

	if fadeOutTime and fadeOutTime > 0 then
		local fade = TweenService:Create(sound, TweenInfo.new(fadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
		fade:Play()
		fade.Completed:Connect(finalize)
	else
		finalize()
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

--- Stops the currently playing background music with a smooth fade-out.
-- @param fadeDuration number? - Duration in seconds for fade-out (default: 1.5)
function AudioModule.stopBGM(fadeDuration: number?)
	if not currentBgmSound then return end

	local duration = fadeDuration or 1.5
	local oldBgm = currentBgmSound
	currentBgmSound = nil

	if duration > 0 then
		local fadeOut = TweenService:Create(oldBgm, TweenInfo.new(duration), { Volume = 0 })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			oldBgm:Stop()
			oldBgm:Destroy()
		end)
	else
		oldBgm:Stop()
		oldBgm:Destroy()
	end
end

--- Configures volume for a specific SoundGroup channel (Master, SFX, Music, UI, Voice).
function AudioModule.setVolume(category: SoundCategory | "Master", volume: number)
	Channels.SetVolume(category, volume)
end

--- [SERVER ONLY] Broadcasts a sound to all connected clients.
-- @param soundInput any - Sound instance, folder name key, or Asset ID
-- @param options PlayOptions?
function AudioModule.playOnAllClients(soundInput: any, options: PlayOptions?)
	if not RunService:IsServer() then
		warn("[AudioModule] playOnAllClients was called on the Client! Use playOneShot instead.")
		AudioModule.playOneShot(soundInput, options)
		return
	end

	local opt = options or {}
	local payload: Types.NetworkSoundPayload = {
		soundInput = soundInput,
		parent = opt.parent,
		position = opt.position,
		volume = opt.volume,
		pitch = opt.pitch,
		pitchVariance = opt.pitchVariance,
		category = opt.category or "SFX",
		rollOffMinDistance = opt.rollOffMinDistance,
		rollOffMaxDistance = opt.rollOffMaxDistance,
		isCombo = opt.isCombo,
		minInterval = opt.minInterval,
	}

	NetworkBridge.send("PlaySound", payload, nil)
end

--- [SERVER ONLY] Plays a sound to a single specific client.
-- @param targetPlayer Player - The Player instance to play sound for
-- @param soundInput any - Sound instance, folder name key, or Asset ID
-- @param options PlayOptions?
function AudioModule.playOnClient(targetPlayer: Player, soundInput: any, options: PlayOptions?)
	if not RunService:IsServer() then
		warn("[AudioModule] playOnClient was called on the Client! Use playOneShot instead.")
		AudioModule.playOneShot(soundInput, options)
		return
	end

	assert(typeof(targetPlayer) == "Instance" and targetPlayer:IsA("Player"), "[AudioModule] targetPlayer must be a valid Player instance!")

	local opt = options or {}
	local payload: Types.NetworkSoundPayload = {
		soundInput = soundInput,
		parent = opt.parent,
		position = opt.position,
		volume = opt.volume,
		pitch = opt.pitch,
		pitchVariance = opt.pitchVariance,
		category = opt.category or "SFX",
		rollOffMinDistance = opt.rollOffMinDistance,
		rollOffMaxDistance = opt.rollOffMaxDistance,
		isCombo = opt.isCombo,
		minInterval = opt.minInterval,
	}

	NetworkBridge.send("PlaySound", payload, targetPlayer)
end

-- Client Auto-Listener: Automatically processes audio packets sent from Server
local clientListenerInitialized = false
local function initClientNetworkListener()
	if clientListenerInitialized or not RunService:IsClient() then return end
	clientListenerInitialized = true

	NetworkBridge.listen("PlaySound", function(payload: any)
		if not payload or not payload.soundInput then return end

		if payload.isCombo then
			AudioModule.playPickupCombo(payload.soundInput, payload.parent)
		else
			AudioModule.playOneShot(payload.soundInput, {
				parent = payload.parent,
				position = payload.position,
				volume = payload.volume,
				pitch = payload.pitch,
				pitchVariance = payload.pitchVariance,
				category = payload.category,
				rollOffMinDistance = payload.rollOffMinDistance,
				rollOffMaxDistance = payload.rollOffMaxDistance,
				minInterval = payload.minInterval,
			})
		end
	end)
end

if RunService:IsClient() then
	task.spawn(initClientNetworkListener)
end

return AudioModule
