--!strict
--[[
    NetworkBridge.luau (AudioModule)
    Self-contained, dual-compatible network adapter bridge for AudioModule.
    Supports ByteNet buffer serialization, standard Roblox RemoteEvents, or Local Standalone mode.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type NetworkProvider = {
	send: (actionName: string, payload: any, targetPlayer: Player?) -> (),
	listen: (actionName: string, callback: (payload: any, player: Player) -> ()) -> (),
}

local NetworkBridge = {}
local customProvider: NetworkProvider? = nil

local function getMode(): "ByteNet" | "RemoteEvent" | "Local"
	if customProvider then
		return "Local"
	end

	local packages = ReplicatedStorage:FindFirstChild("Packages")
	if packages and packages:FindFirstChild("ByteNet") then
		return "ByteNet"
	end

	return "RemoteEvent"
end

local function getRemotesFolder(): Instance
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes and RunService:IsServer() then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Remotes"
		newFolder.Parent = ReplicatedStorage
		return newFolder
	end
	return remotes or ReplicatedStorage
end

local function getRemote(actionName: string): RemoteEvent?
	local remotesFolder = getRemotesFolder()
	local candidateName = "AudioModule_" .. actionName
	local remote = remotesFolder:FindFirstChild(candidateName) or remotesFolder:FindFirstChild(actionName)
	if not remote and RunService:IsServer() then
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = candidateName
		newRemote.Parent = remotesFolder
		remote = newRemote
	end
	return remote :: RemoteEvent?
end

function NetworkBridge.setProvider(provider: NetworkProvider)
	customProvider = provider
end

function NetworkBridge.send(actionName: string, payload: any, targetPlayer: Player?)
	if customProvider then
		customProvider.send(actionName, payload, targetPlayer)
		return
	end

	local mode = getMode()
	if mode == "ByteNet" then
		local byteNetModule = require(ReplicatedStorage.Packages.ByteNet) :: any
		if byteNetModule and byteNetModule.NetworkPackets and byteNetModule.NetworkPackets[actionName] then
			local packet = byteNetModule.NetworkPackets[actionName]
			if RunService:IsClient() then
				packet.send(payload)
			elseif RunService:IsServer() and targetPlayer then
				packet.sendTo(payload, targetPlayer)
			elseif RunService:IsServer() then
				packet.sendAll(payload)
			end
		end
	elseif mode == "RemoteEvent" then
		local remote = getRemote(actionName)
		if remote then
			if RunService:IsClient() then
				remote:FireServer(payload)
			elseif RunService:IsServer() and targetPlayer then
				remote:FireClient(targetPlayer, payload)
			elseif RunService:IsServer() then
				remote:FireAllClients(payload)
			end
		end
	end
end

function NetworkBridge.listen(actionName: string, callback: (payload: any, player: Player) -> ())
	if customProvider then
		customProvider.listen(actionName, callback)
		return
	end

	local mode = getMode()
	if mode == "ByteNet" then
		local byteNetModule = require(ReplicatedStorage.Packages.ByteNet) :: any
		if byteNetModule and byteNetModule.NetworkPackets and byteNetModule.NetworkPackets[actionName] then
			byteNetModule.NetworkPackets[actionName].listen(callback)
		end
	elseif mode == "RemoteEvent" then
		if RunService:IsServer() then
			local remote = getRemote(actionName)
			if remote then
				remote.OnServerEvent:Connect(function(player, payload)
					callback(payload, player)
				end)
			end
		elseif RunService:IsClient() then
			local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5) or ReplicatedStorage
			local candidateName = "AudioModule_" .. actionName
			local remote = remotesFolder:FindFirstChild(candidateName) or remotesFolder:FindFirstChild(actionName)
			if not remote then
				remote = remotesFolder:WaitForChild(candidateName, 8) :: RemoteEvent?
			end
			if remote and remote:IsA("RemoteEvent") then
				remote.OnClientEvent:Connect(function(payload)
					callback(payload, nil :: any)
				end)
			end
		end
	end
end

return NetworkBridge
