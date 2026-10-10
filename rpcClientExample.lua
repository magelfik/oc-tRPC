local rpc = require("rpc").client

io.write("RPC server alias: ")
local serverAlias = io.read()
if not serverAlias or serverAlias == "" then
  error("A server alias is required")
end

rpc.connect(serverAlias)

local function displayResponse(response, availableActions)
  print(response)
  print("Available actions:")
  if #availableActions == 0 then
    print("  none")
    return
  end

  for index, action in ipairs(availableActions) do
    print("  " .. tostring(index) .. ". " .. action)
  end
end

local _, actions = rpc.send("start", displayResponse)

while true do
  if #actions == 0 then
    print("The server kicked you out.")
    break
  end

  io.write("Enter the secret PIN or type disconnect: ")
  local pin = io.read()
  if not pin or pin == "disconnect" then
    rpc.disconnect()
    print("Disconnected.")
    break
  end

  local _, updatedActions = rpc.send(pin, displayResponse)
  actions = updatedActions
end
