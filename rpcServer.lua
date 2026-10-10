local emerald = require("emerald")
local event = require("event")
local filesystem = require("filesystem")
local serialization = require("serialization")

local rpcServer = {}
rpcServer.clients = {}

local BAN_FILE = "/etc/rpc/bans"
local bannedClients = {}
local clientAliases = {}
local processingClientId
local currentRequestKicked = false

local function sendResponse(clientAlias, answer, actions)
	emerald.send(clientAlias, serialization.serialize({
		answer = answer,
		actions = actions
	}))
end

local function validateComputerId(computerId)
	if type(computerId) ~= "string" or computerId == "" then
		error("RPC client computer ID must be a non-empty string", 3)
	end
end

local function loadBans()
	if not filesystem.exists(BAN_FILE) then
		return
	end

  	local file, reason = io.open(BAN_FILE, "r")
  	if not file then
		error("Could not read RPC bans file: " .. tostring(reason), 3)
  	end

  	for computerId in file:lines() do
		if computerId ~= "" then
	  		bannedClients[computerId] = true
		end
  	end

  	local closed, closeReason = file:close()
  	if not closed then
		error("Could not close RPC bans file: " .. tostring(closeReason), 3)
  	end
end

function rpcServer.kick(computerId)
	validateComputerId(computerId)

	local clientAlias = clientAliases[computerId]
  	clientAliases[computerId] = nil
  	rpcServer.clients[computerId] = nil

  	if processingClientId == computerId then
		currentRequestKicked = true
  	end

  	if clientAlias then
		sendResponse(clientAlias, "Disconnected by remote host", {})
  	end
end

function rpcServer.ban(computerId)
	validateComputerId(computerId)

  	if not bannedClients[computerId] then
		if not filesystem.exists("/etc/rpc") then
	  		local created, reason = filesystem.makeDirectory("/etc/rpc")
	  	
			if not created then
				error("Could not create RPC bans directory: " .. tostring(reason), 2)
	  		end
		end

		local file, reason = io.open(BAN_FILE, "a")
		if not file then
	  		error("Could not write RPC bans file: " .. tostring(reason), 2)
		end

		local written, writeReason = file:write(computerId, "\n")
		if not written then
	  		file:close()
	  		error("Could not write RPC bans file: " .. tostring(writeReason), 2)
		end

		local closed, closeReason = file:close()
		if not closed then
	  		error("Could not close RPC bans file: " .. tostring(closeReason), 2)
		end
		bannedClients[computerId] = true
  	end

	rpcServer.kick(computerId)
end

function rpcServer.run(callback)
	if type(callback) ~= "function" then
		error("RPC server callback must be a function", 2)
  	end

  	loadBans()
  	emerald.connect()
  	local serverAlias = emerald.localAlias

  	while true do
		local _, _, _, _, _, flag, clientAlias, to, request = event.pull("modem_message")

		if flag == "MSG" and to == serverAlias then
	  		if type(request) ~= "string" then
				error("RPC message must be serialized text", 2)
	  		end

	  		local message = serialization.unserialize(request)
	  		if type(message) ~= "table" or type(message.computerId) ~= "string" or message.computerId == "" then
				error("RPC message must contain a computer ID", 2)
	  		end

	  		if message.type == "disconnect" then
				sendResponse(clientAlias, "Disconnected", {})
				rpcServer.clients[message.computerId] = nil
				clientAliases[message.computerId] = nil
	  		elseif message.type == "request" and type(message.request) == "string" then
				if bannedClients[message.computerId] then
		  			sendResponse(clientAlias, "Disconnected by remote host", {})
				else
		  			clientAliases[message.computerId] = clientAlias
		  			local clientState = rpcServer.clients[message.computerId]
					if not clientState then
						clientState = {}
						rpcServer.clients[message.computerId] = clientState
		  			elseif type(clientState) ~= "table" then
						error("RPC client state must be a table", 2)
					end

		  			processingClientId = message.computerId
		  			currentRequestKicked = false
		  			local answer, actions = callback(message.request, message.computerId, clientState)
		  			processingClientId = nil
					
					if currentRequestKicked then
						currentRequestKicked = false
		  			else
						if type(answer) ~= "string" then
			  				error("RPC server callback must return answer text", 2)
						end
						
						if type(actions) ~= "table" then
			  				error("RPC server callback must return an actions table", 2)
						end
						
						for _, action in ipairs(actions) do
			  				if type(action) ~= "string" then
								error("RPC server actions must contain only text", 2)
			  				end
						end

						sendResponse(clientAlias, answer, actions)
		  			end
				end
			else
				error("Invalid RPC message", 2)
	  		end
		end
  	end
end

return rpcServer
