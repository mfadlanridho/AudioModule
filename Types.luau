--!strict
--[[
    Types.luau
    Type definitions for AudioModule.
--]]

export type SoundCategory = "SFX" | "Music" | "UI" | "Voice"

export type PlayOptions = {
	volume: number?,
	pitch: number?,
	pitchVariance: number?, -- Random pitch variation (e.g. 0.05 for ±0.05 pitch)
	category: SoundCategory?,
	parent: Instance?,
	loop: boolean?,
	fadeInTime: number?,
}

return {}
