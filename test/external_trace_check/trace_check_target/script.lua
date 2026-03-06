-- Called when a command is entered into chat, does not trigger if sent by server.
---@param full_message string The full message that was sent
---@param peer_id number The peer ID of the player who sent the message
---@param is_admin boolean If the player who entered the command has admin
---@param is_auth boolean If the player who entered the command is authenticated
---@param command string The command the player sent (ex: player entered "?help me", command will be "?help")
---@param ... string The rest of the args of the command, can be packed into a table with "arg = table.pack(...)" and referenced with "arg[1]", "arg[2]", ect
function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, ...)
	if command == "?error" then
		error("This function doesn't actually exist!")
	elseif command == "ssswtool_trace_error" then
		-- We can detect our own errors immediately after they happen!
		-- This is run before any other SW callback gets run.
		-- Though, other addons `onCustomCommand` may be called before this addon.
		local addonIndex = tonumber(...)
		if addonIndex == server.getAddonIndex() then
			debug.log("[SW] [SSSWTool-check-target] Oh no we had an error!")
		end
	end
end

function onTick()
	-- debug.log("onTick()")
	-- Test error
	-- error("This function doesn't actually exist!")
end
