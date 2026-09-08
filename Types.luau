--!strict
--[[
    Types.luau
    Type definitions for AudioModule.
--]]

export type SoundCategory = "Master" | "SFX" | "Music" | "UI" | "Voice"

export type SoundConfig = {
	soundId: string,
	volume: number?,
	pitch: number?,
	category: SoundCategory?,
}

export type PlayOptions = {
	volume: number?,
	pitch: number?,
	pitchVariance: number?, -- Random pitch variation (e.g. 0.05 for ±0.05 pitch)
	category: SoundCategory?,
	parent: Instance?,
	position: Vector3?, -- 3D world position (creates temporary attachment)
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?,
	rollOffMode: Enum.RollOffMode?,
	loop: boolean?,
	fadeInTime: number?,
	isCombo: boolean?,
}

export type NetworkSoundPayload = {
	soundInput: any,
	parent: Instance?,
	position: Vector3?,
	volume: number?,
	pitch: number?,
	pitchVariance: number?,
	category: SoundCategory?,
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?,
	isCombo: boolean?,
}

return {}

