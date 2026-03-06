---@param game_ticks number
function onTick(game_ticks)
	server.command("?ssswtool_trace_check")
end

---@param full_message string
---@param peer_id number
---@param is_admin boolean
---@param is_auth boolean
---@param command string
---@param ... string
function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, ...)
	-- Example of a traced addon error;
	-- 'ssswtool_trace_error 0'
	-- Where the `0` is the addon index.

	if command == "ssswtool_trace_error" then
		local addonIndex = tonumber(...)
		debug.log(("[SW] [SSSWTool-trace-check] %s \"%s\""):format(addonIndex, server.getAddonData(addonIndex).name))
	end
end
