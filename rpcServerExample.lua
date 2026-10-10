local rpcServer = require("rpcServer")

local SECRET_PIN = "171263"

local function handleRequest(request, computerId, state)
  state.failures = state.failures or 0

  if state.failures >= 3 then
    rpcServer.kick(computerId)
    return "Too many failed attempts. You have been kicked out by the server.", {}
  end

  if request == "start" then
    return "Enter the secret PIN to continue.", { "submit pin" }
  elseif request == SECRET_PIN then
    state.failures = 0
    return "Access granted. Welcome.", { "show status", "disconnect" }
  else
    state.failures = state.failures + 1
    if state.failures >= 3 then
      rpcServer.kick(computerId)
      return "Incorrect PIN. Too many failed attempts. You have been kicked out by the server.", {}
    end

    local remaining = 3 - state.failures
    return "Incorrect PIN. " .. tostring(remaining) .. " attempt(s) remaining.", { "submit pin" }
  end
end

rpcServer.run(handleRequest)
