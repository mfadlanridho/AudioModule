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

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AudioModule = require(ReplicatedStorage.Packages.AudioModule)

-- 1. Play a 2D or 3D SFX with random pitch variance
AudioModule.playOneShot("CoinPickup", {
    pitchVariance = 0.05,
    category = "SFX",
})

-- 2. Play rapid pickup combo audio
AudioModule.playPickupCombo("CoinPickup")

-- 3. Cross-fade Background Music (BGM)
AudioModule.playBGM("ThemeSong", 2.0)

-- 4. Adjust Channel Volumes from Settings Menu
AudioModule.setVolume("Music", 0.3)
AudioModule.setVolume("SFX", 0.8)
```

---

## 📄 License
MIT License - Free for use across all your Roblox projects.
