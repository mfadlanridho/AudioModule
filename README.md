# 🔊 Standalone AudioModule

A zero-dependency, self-contained Audio Engine package for Roblox games.

---

## 📂 Package Architecture

```text
AudioModule/
├── init.luau       -- Main audio manager (playOneShot, playLooped, setNetworkProvider)
├── NetworkBridge.luau-- Dual-compatible network adapter (ByteNet / RemoteEvents / Local)
├── Channels.luau   -- SoundGroup channel hierarchy manager (Master, SFX, Music, UI, Voice)
├── Types.luau      -- Luau type definitions
└── README.md       -- Package documentation & code examples
```

---

## 🛠 Features

- 🔌 **100% Plug & Play**: Drop into any project and start calling functions immediately with zero configuration required.
- 🎚 **SoundGroup Channels**: Automatically manages `Master`, `SFX`, `Music`, `UI`, and `Voice` channels for settings menus.
- 🌐 **Dual Networking Adapter**: Built-in auto-detection for **ByteNet** buffer serialization, native **RemoteEvents**, or **Local Standalone** mode.
- 🎲 **Random Pitch Variance**: Add pitch randomization (`pitchVariance = 0.05`) to prevent repetitive audio fatigue.
- 📈 **Combo Pitch Scaling**: `playPickupCombo()` automatically scales pitch up from `1.0` -> `1.5` for streak feedback.
- 🎵 **BGM Cross-Fading**: Smoothly cross-fade background music tracks using `TweenService`.
- 🔁 **Tracked Loops**: Start and stop looped sounds cleanly with optional fade-out timers.
- 🧩 **Studio Sound Templates**: `Sound` instances placed in `SoundService` or `ReplicatedStorage.Audio` are cloned on play, so every property and child effect (EQ, reverb, ...) set in Studio is kept.

---

## 🌐 Dual Networking & Custom Providers

`AudioModule` includes a self-contained `NetworkBridge.luau` that automatically detects the host project environment:
1. **ByteNet Mode**: If `ReplicatedStorage.Packages.ByteNet` exists, it routes network events over ByteNet buffers.
2. **RemoteEvent Mode**: If `ReplicatedStorage.Remotes` or `RemoteEvents` exist, it routes over Roblox `RemoteEvents`.
3. **Local Standalone Mode**: If no networking library is found, it runs locally without errors.

### Explicit Custom Provider Override
```luau
AudioModule.setNetworkProvider({
    send = function(actionName, payload, targetPlayer)
        -- Route through custom network handler
    end,
    listen = function(actionName, callback)
        -- Route listener
    end,
})
```

---

## 🚀 Usage Example

### Client-Side Playback
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AudioModule = require(ReplicatedStorage.Packages.AudioModule)

-- 1. Register named sound dictionary (optional, bypasses physical sound folders)
AudioModule.registerSounds({
    CoinPickup = "rbxassetid://12345678",
    EggGrab = { soundId = "rbxassetid://87654321", volume = 0.8, pitch = 1.0, category = "SFX" },
})

-- 2. Play a 2D or 3D SFX with random pitch variance or 3D world position
AudioModule.playOneShot("CoinPickup", {
    pitchVariance = 0.05,
    category = "SFX",
    position = Vector3.new(0, 10, 0), -- 3D world position
    rollOffMaxDistance = 100,
})

-- 3. Play rapid pickup combo audio
AudioModule.playPickupCombo("CoinPickup")

-- 4. Play, cross-fade, or stop Background Music (BGM)
AudioModule.playBGM("ThemeSong", 2.0)
AudioModule.stopBGM(1.5)

-- 5. Adjust Channel Volumes from Settings Menu (Master, SFX, Music, UI, Voice)
AudioModule.setVolume("Master", 1.0)
AudioModule.setVolume("Music", 0.3)
AudioModule.setVolume("SFX", 0.8)
```

### Server-Side Network Playback (Isomorphic / Universal)
When required on the server, `AudioModule` provides zero-boilerplate broadcast and targeted client audio:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AudioModule = require(ReplicatedStorage.Packages.AudioModule)

-- 1. Broadcast 3D sound to all connected clients
AudioModule.playOnAllClients("RagdollHit", {
    parent = victimHrp,
    volume = 0.8,
})

-- 2. Play targeted sound for a specific player (e.g. combo pickup or private UI)
AudioModule.playOnClient(player, "CoinPickup", {
    isCombo = true,
})
```
*Note: Clients automatically listen and play server-triggered audio the moment `AudioModule` is required on the client.*

---

## 📄 License
MIT License - Free for use across all your Roblox projects.
