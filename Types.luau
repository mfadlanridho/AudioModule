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
	isCombo: boolean?,
}

export type NetworkSoundPayload = {
	soundInput: any,
	parent: Instance?,
	volume: number?,
	pitch: number?,
	pitchVariance: number?,
	category: SoundCategory?,
	isCombo: boolean?,
}

return {}

