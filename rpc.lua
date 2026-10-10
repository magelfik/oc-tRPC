local emerald = require("emerald")
local event = require("event")
local computer = require("computer")
local serialization = require("serialization")

local rpc = {}
local serverAlias
local DEFAULT_TIMEOUT = 30
local clientId = computer.address()

local function checkTimeout(timeout)
	if timeout == nil then
		return DEFAULT_TIMEOUT
	end

	if type(timeout) ~= "number" or timeout <= 0 or timeout == math.huge or timeout ~= timeout then
		error("Timeout must be a positive finite number", 3)
	end

	return timeout
end

local function receiveResponse(timeout, callback)
	local deadline = computer.uptime() + timeout

	while true do
		local remaining = deadline - computer.uptime()
		if remaining <= 0 then
			error("Timed out waiting for RPC server response", 3)
		end

		local _, flag, response = event.pull(remaining, "emerald")
		if not flag then
			error("Timed out waiting for RPC server response", 3)
		elseif flag == "MSG" then
			if type(response) ~= "string" then
				error("RPC server response must be serialized text", 3)
			end

			local decoded = serialization.unserialize(response)
			if type(decoded) ~= "table" or type(decoded.answer) ~= "string" or type(decoded.actions) ~= "table" then
				local answerType = type(decoded) == "table" and type(decoded.answer) or "unavailable"
				local actionsType = type(decoded) == "table" and type(decoded.actions) or "unavailable"
				error("Invalid RPC response (decoded as " .. type(decoded) .. ", answer is " .. answerType .. ", actions is " .. actionsType .. "); expected an answer string and an actions table", 3)
			end
			for index, action in ipairs(decoded.actions) do
				if type(action) ~= "string" then
					error("RPC server actions must contain only text", 3)
				end
			end

			if callback then
				callback(decoded.answer, decoded.actions)
			end
			return decoded.answer, decoded.actions
		end
	end
end

function rpc.connect(alias)
	if type(alias) ~= "string" or alias == "" then
		error("RPC server alias must be a non-empty string", 2)
	end

	if serverAlias then
		error("Already connected to an RPC server", 2)
	end

	emerald.connect()
	serverAlias = alias
end

function rpc.send(request, callback, timeout)
	if not serverAlias then
		error("Not connected to an RPC server", 2)
	end
	if type(request) ~= "string" then
		error("RPC request must be text", 2)
	end
	if callback ~= nil and type(callback) ~= "function" then
		error("RPC response callback must be a function or nil", 2)
	end

	timeout = checkTimeout(timeout)
	emerald.send(serverAlias, serialization.serialize({
		type = "request",
		computerId = clientId,
		request = request
	}))
	local answer, actions = receiveResponse(timeout, callback)
	if #actions == 0 then
		emerald.disconnect()
		serverAlias = nil
	end
	return answer, actions
end

function rpc.disconnect()
	if not serverAlias then
		error("Not connected to an RPC server", 2)
	end

	emerald.send(serverAlias, serialization.serialize({
		type = "disconnect",
		computerId = clientId
	}))
	receiveResponse(DEFAULT_TIMEOUT)
	emerald.disconnect()
	serverAlias = nil
end

function rpc.getServer()
	return serverAlias
end

return rpc
